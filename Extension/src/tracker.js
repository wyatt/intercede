// Usage and budget rules, as pure functions over plain data (no chrome.* calls), so they can be
// tested in Node. Mirrors the rules in Intercede/Usage/UsageTracker.swift.

export const DEFAULT_SITES = [
  'youtube.com', 'instagram.com', 'x.com', 'reddit.com', 'tiktok.com', 'facebook.com',
].map(host => ({ host, dailyBudgetSeconds: 15 * 60 }));

export const BREACH_COOLDOWN_MS = 5 * 60 * 1000;
export const MINUTE_RANGE = [1, 1440];

/** Lowercased, without a leading "www.". */
export function normalizeHost(host) {
  const h = (host ?? '').toLowerCase();
  return h.startsWith('www.') ? h.slice(4) : h;
}

/** Host from user input: a bare domain or a pasted URL. Null if it isn't a usable site. */
export function hostFromInput(input) {
  const trimmed = (input ?? '').trim();
  if (!trimmed || /\s/.test(trimmed)) return null;
  try {
    const host = normalizeHost(new URL(trimmed.includes('://') ? trimmed : `https://${trimmed}`).hostname);
    return host.includes('.') ? host : null;
  } catch {
    return null;
  }
}

/** The most specific tracked site matching `host` (exact, or a parent domain), or null. */
export function siteFor(sites, host) {
  const h = normalizeHost(host);
  let best = null;
  for (const site of sites) {
    const s = normalizeHost(site.host);
    if ((h === s || h.endsWith(`.${s}`)) && (!best || s.length > normalizeHost(best.host).length)) best = site;
  }
  return best;
}

/** Local calendar day, "YYYY-MM-DD". */
export function dayKey(date) {
  const pad = n => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/** Seconds used today on a site (usage is keyed by the configured site, so subdomains share it). */
export function secondsUsed(usage, sites, host) {
  const site = siteFor(sites, host);
  return usage?.[normalizeHost(site ? site.host : host)] ?? 0;
}

/**
 * Credits `seconds` on `host` to today's usage. Returns the updated usage and, if this pushed the
 * site over budget and it's outside the cooldown, the site to nudge about (and the updated cooldowns).
 */
export function credit({ usage = {}, sites, host, seconds, now, lastBreach = {} }) {
  const site = siteFor(sites, host);
  if (!site || !(seconds > 0)) return { usage, breach: null, lastBreach };
  const key = normalizeHost(site.host);
  const next = { ...usage, [key]: (usage[key] ?? 0) + seconds };
  if (next[key] < site.dailyBudgetSeconds) return { usage: next, breach: null, lastBreach };
  if (lastBreach[key] !== undefined && now - lastBreach[key] < BREACH_COOLDOWN_MS) {
    return { usage: next, breach: null, lastBreach };
  }
  return { usage: next, breach: site, lastBreach: { ...lastBreach, [key]: now } };
}

export function addSite(sites, input, budgetSeconds = 15 * 60) {
  const host = hostFromInput(input);
  if (!host || sites.some(s => normalizeHost(s.host) === host)) return { ok: false, sites };
  return { ok: true, sites: [...sites, { host, dailyBudgetSeconds: budgetSeconds }] };
}

export function removeSite(sites, host) {
  const h = normalizeHost(host);
  return sites.filter(s => normalizeHost(s.host) !== h);
}

/** Minutes from a typed value, clamped to 1 minute – 24 hours; null if it isn't a number. */
export function clampMinutes(value) {
  const n = Math.round(Number(value));
  if (!Number.isFinite(n)) return null;
  return Math.min(Math.max(n, MINUTE_RANGE[0]), MINUTE_RANGE[1]);
}
