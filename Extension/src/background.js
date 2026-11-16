// Intercede extension background worker.
//
// Holds a Native Messaging port to the Intercede app (via the IntercedeBridge helper) and turns its
// nudge beats into page effects on exactly one tab:
//   hold     → pause media, dim           (patron raises his hand)
//   dissolve → snapshot + pixel dissolve   (patron sweeps it away), then the veil
//   release  → undo a hold that never became a dissolve
// The app broadcasts to every connected browser; each acts only if one of its windows is focused
// and its active tab is on the nudged site (or any site, for Test Nudge).

const HOST_NAME = 'com.intercede.bridge';
const PROTOCOL = 1;
const RECONNECT_MIN_MS = 2000;
const RECONNECT_MAX_MS = 60000;

let port = null;
let reconnectDelay = RECONNECT_MIN_MS;
let reconnectTimer = null;
const nudgeTabs = new Map();  // nudgeId → tabId, so release/dissolve hit the tab that was held

// ── Connection ───────────────────────────────────────────────────────────────

function connect() {
  if (port) return;
  clearTimeout(reconnectTimer);
  try {
    port = chrome.runtime.connectNative(HOST_NAME);
  } catch (e) {
    console.warn('[intercede] connectNative threw', e);
    return scheduleReconnect();
  }
  port.onMessage.addListener(onAppMessage);
  port.onDisconnect.addListener(() => {
    console.warn('[intercede] bridge disconnected:', chrome.runtime.lastError?.message);
    port = null;
    scheduleReconnect();
  });
  send({ type: 'hello', browser: browserName(), extensionVersion: chrome.runtime.getManifest().version });
}

function scheduleReconnect() {
  clearTimeout(reconnectTimer);
  reconnectTimer = setTimeout(connect, reconnectDelay);
  reconnectDelay = Math.min(reconnectDelay * 2, RECONNECT_MAX_MS);
}

function send(message) {
  try { port?.postMessage({ v: PROTOCOL, ...message }); } catch (e) { console.warn('[intercede] send failed', e); }
}

function browserName() {
  const brands = navigator.userAgentData?.brands?.map(b => b.brand) ?? [];
  return ['Brave', 'Microsoft Edge', 'Opera', 'Google Chrome', 'Chromium'].find(b => brands.includes(b)) ?? 'Chromium';
}

// The open port keeps this worker alive; these cover browser start and the worker being evicted.
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
chrome.alarms.create('intercede-keepalive', { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener(() => connect());
connect();

// ── App → page ───────────────────────────────────────────────────────────────

async function onAppMessage(msg) {
  if (msg?.v !== PROTOCOL) return;
  if (msg.type === 'connected') { reconnectDelay = RECONNECT_MIN_MS; return; }
  if (msg.type === 'appUnavailable') return;  // helper keeps retrying the app on its own
  try {
    if (msg.type === 'hold') await onHold(msg);
    else if (msg.type === 'dissolve') await onDissolve(msg);
    else if (msg.type === 'release') await onRelease(msg);
  } catch (e) {
    ack(msg, false, String(e?.message ?? e));
  }
}

async function onHold(msg) {
  const tab = await targetTab(msg);
  if (!tab) return ack(msg, false, 'no matching focused tab');
  nudgeTabs.set(msg.nudgeId, tab.id);
  await inject(tab.id);
  const [{ result }] = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: () => IntercedeDissolve.hold(),
  });
  ack(msg, true, `paused ${result?.paused ?? 0} media`);
}

async function onDissolve(msg) {
  // Dissolve the tab we held if there was one; otherwise find a target now (e.g. hold was skipped).
  let tabId = nudgeTabs.get(msg.nudgeId);
  if (tabId === undefined) {
    const tab = await targetTab(msg);
    if (!tab) return ack(msg, false, 'no matching focused tab');
    tabId = tab.id;
    nudgeTabs.set(msg.nudgeId, tabId);
  }
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (!tab?.active) return ack(msg, false, 'held tab is gone or no longer active');

  await inject(tabId);
  // Snapshot what's on screen right now (dimmed by hold) so the dissolve starts seamlessly.
  const snapshot = await chrome.tabs.captureVisibleTab(tab.windowId, { format: 'jpeg', quality: 85 })
    .catch(e => { console.warn('[intercede] capture failed, using cover mode', e); return null; });

  const [{ result }] = await chrome.scripting.executeScript({
    target: { tabId },
    args: [{
      snapshot,
      durationMs: msg.durationMs,
      patronName: msg.patronName,
      catchphrase: msg.catchphrase,
      phrase: msg.phrase,
      nudgeId: msg.nudgeId,
      host: msg.host,
    }],
    func: async options => IntercedeDissolve.dissolve({
      ...options,
      onReturn: () => chrome.runtime.sendMessage({ type: 'returnAnyway', nudgeId: options.nudgeId, host: options.host }),
    }),
  });
  nudgeTabs.delete(msg.nudgeId);
  ack(msg, !!result?.ok, result?.reason ?? result?.mode);
}

async function onRelease(msg) {
  const tabId = nudgeTabs.get(msg.nudgeId);
  nudgeTabs.delete(msg.nudgeId);
  if (tabId === undefined) return;
  await chrome.scripting.executeScript({
    target: { tabId },
    func: () => globalThis.IntercedeDissolve?.release(),
  }).catch(() => {});
  ack(msg, true, 'released');
}

function ack(msg, ok, reason) {
  send({ type: 'ack', nudgeId: msg.nudgeId, for: msg.type, ok, reason });
}

// ── Page → app ───────────────────────────────────────────────────────────────

chrome.runtime.onMessage.addListener((message, sender) => {
  if (sender.id !== chrome.runtime.id || message?.type !== 'returnAnyway') return;
  send({ type: 'returnAnyway', nudgeId: message.nudgeId, host: message.host });
});

// ── Targeting ────────────────────────────────────────────────────────────────

// The active tab of this browser's focused window, if it's on the nudged site. Test nudges accept
// any web page and the last-focused window, since clicking the menu bar takes focus away.
async function targetTab(msg) {
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!tab?.url || !/^https?:/.test(tab.url)) return null;
  if (msg.test) return tab;
  const win = await chrome.windows.get(tab.windowId);
  if (!win.focused) return null;
  return hostMatches(new URL(tab.url).hostname, msg.host) ? tab : null;
}

// Same rule as UsageTracker: case-insensitive, ignore "www.", subdomains count.
function hostMatches(tabHost, siteHost) {
  const norm = h => (h || '').toLowerCase().replace(/^www\./, '');
  const t = norm(tabHost), s = norm(siteHost);
  return !!s && (t === s || t.endsWith('.' + s));
}

async function inject(tabId) {
  await chrome.scripting.executeScript({ target: { tabId }, files: ['src/dissolve.js'] });
}
