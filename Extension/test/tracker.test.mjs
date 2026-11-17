// Usage rules. Run: make ext-test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  credit, siteFor, secondsUsed, hostFromInput, addSite, removeSite, clampMinutes, dayKey, BREACH_COOLDOWN_MS,
} from '../src/tracker.js';

const site = (host, minutes = 60) => ({ host, dailyBudgetSeconds: minutes * 60 });

test('accumulates time on a tracked site', () => {
  const sites = [site('youtube.com')];
  let { usage } = credit({ sites, host: 'youtube.com', seconds: 2, now: 0 });
  ({ usage } = credit({ usage, sites, host: 'youtube.com', seconds: 2, now: 0 }));
  assert.equal(secondsUsed(usage, sites, 'youtube.com'), 4);
});

test('www. and subdomains count toward the configured site', () => {
  const sites = [site('reddit.com')];
  let { usage } = credit({ sites, host: 'www.Reddit.com', seconds: 2, now: 0 });
  ({ usage } = credit({ usage, sites, host: 'old.reddit.com', seconds: 3, now: 0 }));
  assert.deepEqual(usage, { 'reddit.com': 5 });
});

test('the most specific site wins; look-alike domains do not match', () => {
  const sites = [site('google.com'), site('news.google.com', 1), site('x.com')];
  assert.equal(siteFor(sites, 'news.google.com').host, 'news.google.com');
  assert.equal(siteFor(sites, 'mail.google.com').host, 'google.com');
  assert.equal(siteFor(sites, 'box.com'), null);
});

test('untracked sites are ignored', () => {
  const { usage, breach } = credit({ sites: [site('youtube.com')], host: 'github.com', seconds: 10, now: 0 });
  assert.deepEqual(usage, {});
  assert.equal(breach, null);
});

test('a breach fires with the configured host, then respects the cooldown', () => {
  const sites = [{ host: 'youtube.com', dailyBudgetSeconds: 2 }];
  let r = credit({ sites, host: 'm.youtube.com', seconds: 2, now: 0 });
  assert.equal(r.breach?.host, 'youtube.com');
  r = credit({ usage: r.usage, sites, host: 'youtube.com', seconds: 2, now: 60_000, lastBreach: r.lastBreach });
  assert.equal(r.breach, null, 'within cooldown');
  r = credit({ usage: r.usage, sites, host: 'youtube.com', seconds: 2, now: BREACH_COOLDOWN_MS + 1, lastBreach: r.lastBreach });
  assert.equal(r.breach?.host, 'youtube.com', 'after cooldown');
});

test('day keys are local calendar days', () => {
  assert.equal(dayKey(new Date(2026, 10, 16, 23, 59)), '2026-11-16');
  assert.equal(dayKey(new Date(2026, 0, 2, 0, 1)), '2026-01-02');
});

test('site input accepts bare hosts and pasted URLs', () => {
  assert.equal(hostFromInput('https://www.Twitch.tv/somestreamer'), 'twitch.tv');
  assert.equal(hostFromInput('YouTube.com/watch'), 'youtube.com');
  assert.equal(hostFromInput('not a site'), null);
  assert.equal(hostFromInput('localhost'), null);
  assert.equal(hostFromInput(''), null);
});

test('adding and removing sites', () => {
  let { ok, sites } = addSite([site('youtube.com')], 'https://www.twitch.tv/x');
  assert.ok(ok);
  assert.equal(sites.at(-1).host, 'twitch.tv');
  assert.equal(addSite(sites, 'www.youtube.com').ok, false, 'duplicate');
  sites = removeSite(sites, 'WWW.YouTube.com');
  assert.deepEqual(sites.map(s => s.host), ['twitch.tv']);
});

test('typed minutes are clamped to 1–1440', () => {
  assert.equal(clampMinutes('0'), 1);
  assert.equal(clampMinutes('5000'), 1440);
  assert.equal(clampMinutes('22.6'), 23);
  assert.equal(clampMinutes('abc'), null);
});
