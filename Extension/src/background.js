// Intercede background worker: tracks time on distracting sites and sends a patron when a site's
// daily budget runs out.
//
// Tracking is event-driven, because MV3 workers are suspended when idle and can't keep timers.
// The "current interval" (which tab/site has the user's attention, and since when) lives in
// storage.session; every change of attention (tab switch, navigation, window focus, screen lock)
// closes it and credits the elapsed time. A one-minute alarm flushes it periodically, which also
// caps how much time an unobserved gap (e.g. the Mac sleeping) can add.

import { DEFAULT_SITES, credit, dayKey } from './tracker.js';
import { LAYOUT, patronFor, randomPhrase, DEFAULT_PATRON } from './patrons.js';

const FLUSH_MINUTES = 1;
const MAX_INTERVAL_S = 90;  // longer than this between flushes means we weren't observing

// ── Storage ──────────────────────────────────────────────────────────────────

async function settings() {
  const { sites, patron } = await chrome.storage.sync.get(['sites', 'patron']);
  return { sites: sites ?? DEFAULT_SITES, patron: patron ?? DEFAULT_PATRON };
}

const usageKey = date => `usage:${dayKey(date)}`;

// ── Attention tracking ───────────────────────────────────────────────────────

// Serialize all state changes: chrome.* calls are async and events can arrive together.
let queue = Promise.resolve();
const serial = fn => (queue = queue.then(fn).catch(e => console.warn('[intercede]', e)));

/** Which site has the user's attention right now: the active tab of a focused Chrome window. */
async function attention() {
  const { locked } = await chrome.storage.session.get('locked');
  if (locked) return null;
  const win = await chrome.windows.getLastFocused().catch(() => null);
  if (!win?.focused) return null;
  const [tab] = await chrome.tabs.query({ active: true, windowId: win.id });
  if (!tab?.url || !/^https?:/.test(tab.url)) return null;
  return { tabId: tab.id, host: new URL(tab.url).hostname };
}

/** Credit the open interval up to now and keep it open. */
async function flush(now = Date.now()) {
  const { current } = await chrome.storage.session.get('current');
  if (!current) return;
  const seconds = Math.min((now - current.since) / 1000, MAX_INTERVAL_S);
  await chrome.storage.session.set({ current: { ...current, since: now } });
  await creditTime(current.host, current.tabId, seconds, new Date(now));
}

/** Close the open interval and start a new one for whatever has attention now. */
async function refresh() {
  await flush();
  const next = await attention();
  await chrome.storage.session.set({ current: next ? { ...next, since: Date.now() } : null });
}

async function creditTime(host, tabId, seconds, now) {
  const { sites } = await settings();
  const key = usageKey(now);
  const stored = await chrome.storage.local.get([key, 'lastBreach']);
  const result = credit({ usage: stored[key], sites, host, seconds, now: now.getTime(), lastBreach: stored.lastBreach ?? {} });
  await chrome.storage.local.set({ [key]: result.usage, lastBreach: result.lastBreach });
  if (result.breach) nudge(tabId, result.breach.host);
}

chrome.tabs.onActivated.addListener(() => serial(refresh));
chrome.tabs.onUpdated.addListener((_id, change, tab) => { if (change.url && tab.active) serial(refresh); });
chrome.windows.onFocusChanged.addListener(() => serial(refresh));
chrome.idle.onStateChanged.addListener(state => serial(async () => {
  // Only a locked screen pauses tracking. "idle" (no input) is ignored: watching a video is idle.
  if (state === 'idle') return;
  if (state === 'locked') { await flush(); await chrome.storage.session.set({ locked: true, current: null }); }
  else { await chrome.storage.session.set({ locked: false }); await refresh(); }
}));
chrome.alarms.create('intercede-flush', { periodInMinutes: FLUSH_MINUTES });
chrome.alarms.onAlarm.addListener(alarm => { if (alarm.name === 'intercede-flush') serial(refresh); });
chrome.runtime.onStartup.addListener(() => serial(refresh));
chrome.runtime.onInstalled.addListener(async ({ reason }) => {
  if (reason === 'install') chrome.runtime.openOptionsPage();
  serial(refresh);
});

// ── Nudges ───────────────────────────────────────────────────────────────────

const presenting = new Set();  // tab ids with a patron on screen

/** Sends the selected patron onto `tabId`. `host` is the site over budget, or null for a test. */
async function nudge(tabId, host) {
  if (presenting.has(tabId)) return;
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (!tab?.url || !/^https?:/.test(tab.url)) return;  // Chrome's own pages can't be scripted
  const patron = patronFor((await settings()).patron);
  presenting.add(tabId);
  try {
    await chrome.scripting.executeScript({ target: { tabId }, files: ['src/dissolve.js', 'src/patron.js'] });
    await chrome.scripting.executeScript({
      target: { tabId },
      args: [{
        sheetUrl: chrome.runtime.getURL(`patrons/${patron.sheet}.png`),
        layout: LAYOUT,
        name: patron.name,
        catchphrase: patron.catchphrase,
        phrase: randomPhrase(patron, host),
      }],
      func: options => { IntercedePatron.present(options); },
    });
  } catch (e) {
    presenting.delete(tabId);
    console.warn('[intercede] could not nudge tab', tabId, e);
  }
}

chrome.tabs.onRemoved.addListener(tabId => presenting.delete(tabId));

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (sender.id !== chrome.runtime.id) return;
  switch (message?.type) {
    case 'testNudge':  // from the popup: the active tab of the window it was opened from
      chrome.tabs.query({ active: true, lastFocusedWindow: true }).then(([tab]) => tab && nudge(tab.id, null));
      return;
    case 'capture':  // from the page: snapshot it for the dissolve (only the extension can)
      chrome.tabs.captureVisibleTab(sender.tab.windowId, { format: 'jpeg', quality: 85 })
        .then(reply, () => reply(null));
      return true;  // reply asynchronously
    case 'flush':  // the popup is opening: bring today's numbers up to date
      serial(refresh);
      return;
    case 'patronDone':
      presenting.delete(sender.tab?.id);
      return;
    case 'returnAnyway':
      console.info('[intercede] return anyway on', sender.tab?.url);
      return;
  }
});

// Debug handle for the service worker console / automated checks.
globalThis.intercede = { refresh: () => serial(refresh), nudge };
