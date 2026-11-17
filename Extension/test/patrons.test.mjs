// Patron data: every sheet must exist, phrases fill in the site, frame timing loops or holds.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { PATRONS, randomPhrase, frameIndex, LAYOUT } from '../src/patrons.js';

const root = fileURLToPath(new URL('../../', import.meta.url));

test('every patron has a bundled sheet in the extension', () => {
  for (const p of PATRONS) assert.ok(existsSync(root + `Extension/patrons/${p.sheet}.png`), p.sheet);
});

test('phrases without a host never name a site', () => {
  for (const p of PATRONS) {
    for (let i = 0; i < 50; i++) assert.ok(!randomPhrase(p, null).includes('%@'), p.name);
    assert.ok(!randomPhrase(p, 'youtube.com').includes('%@'));
  }
});

test('frame timing loops or holds', () => {
  assert.equal(frameIndex(LAYOUT.clips.walkIn, 1000 * 5 / 9 + 1), 5);
  assert.equal(frameIndex(LAYOUT.clips.walkIn, 1000 * 6 / 9 + 1), 0);
  assert.equal(frameIndex(LAYOUT.clips.dismiss, 10_000), 5);
});
