// Settings page: tracked sites with daily limits, and the patron picker.
import { DEFAULT_SITES, addSite, removeSite, clampMinutes } from './tracker.js';
import { PATRONS, DEFAULT_PATRON, LAYOUT, frameIndex } from './patrons.js';

const $ = id => document.getElementById(id);
let sites = [];

// ── Sites ──

async function loadSites() {
  ({ sites = DEFAULT_SITES } = await chrome.storage.sync.get('sites'));
  renderSites();
}

const saveSites = () => chrome.storage.sync.set({ sites });

function renderSites() {
  const rows = $('site-rows');
  rows.replaceChildren();
  if (!sites.length) {
    rows.append(Object.assign(document.createElement('div'), { className: 'empty muted', textContent: 'No sites tracked yet.' }));
  }
  for (const site of sites) {
    const row = document.createElement('div');
    row.className = 'row';
    row.innerHTML = `
      <span class="host"></span>
      <input type="number" min="1" max="1440" step="1">
      <span class="unit muted">min / day</span>
      <button class="remove" type="button" title="Remove">−</button>`;
    row.querySelector('.host').textContent = site.host;
    const minutes = row.querySelector('input');
    minutes.value = Math.round(site.dailyBudgetSeconds / 60);
    minutes.setAttribute('aria-label', `Daily limit for ${site.host}, in minutes`);
    minutes.addEventListener('change', () => {
      const value = clampMinutes(minutes.value) ?? Math.round(site.dailyBudgetSeconds / 60);
      minutes.value = value;
      site.dailyBudgetSeconds = value * 60;
      saveSites();
    });
    const remove = row.querySelector('.remove');
    remove.setAttribute('aria-label', `Stop tracking ${site.host}`);
    remove.addEventListener('click', () => {
      sites = removeSite(sites, site.host);
      saveSites();
      renderSites();
    });
    rows.append(row);
  }
}

$('add-form').addEventListener('submit', event => {
  event.preventDefault();
  const result = addSite(sites, $('new-host').value);
  if (!result.ok) {
    $('add-error').textContent = 'Not a valid site, or already tracked.';
    return;
  }
  sites = result.sites;
  saveSites();
  renderSites();
  $('new-host').value = '';
  $('add-error').textContent = '';
});
$('new-host').addEventListener('input', () => { $('add-error').textContent = ''; });

// ── Patron ──
// A looping lineup: the chosen patron stands large in the middle, the others smaller (all the
// same size) to either side, wrapping around.

const scale = 150 / LAYOUT.frameHeight;
const SLOTS = [  // by distance from the middle
  { x: 0, size: 1.25, opacity: 1 },
  { x: 132, size: 0.6, opacity: 0.75 },
  { x: 222, size: 0.6, opacity: 0.75 },
];
const HIDDEN = { x: 300, size: 0.3, opacity: 0 };
const cards = [];  // { patron, card, offset }
let chosen = 0;    // index into PATRONS

function renderPatrons() {
  for (const patron of PATRONS) {
    const card = document.createElement('button');
    card.type = 'button';
    card.className = 'patron-card sprite';
    card.setAttribute('role', 'radio');
    card.setAttribute('aria-label', patron.name);
    card.style.backgroundImage = `url("patrons/${patron.sheet}.png")`;
    card.style.backgroundSize = `${LAYOUT.cols * LAYOUT.frameWidth * scale}px ${LAYOUT.rows * LAYOUT.frameHeight * scale}px`;
    const entry = { patron, card, offset: null };
    card.addEventListener('click', () => choose(cards.indexOf(entry)));
    cards.push(entry);
    $('patrons').append(card);
  }
}

function choose(index, save = true) {
  const n = cards.length;
  chosen = (index + n) % n;
  for (const [i, entry] of cards.entries()) {
    let offset = (i - chosen + n) % n;
    if (offset > n / 2) offset -= n;  // nearest way round
    const slot = SLOTS[Math.abs(offset)] ?? HIDDEN;
    const at = `translateX(${Math.sign(offset) * slot.x}px) scale(${slot.size})`;
    // A card wrapping from one end to the other jumps instead of sliding across the middle.
    const wraps = entry.offset !== null && Math.abs(offset - entry.offset) > 1;
    if (wraps) entry.card.style.transition = 'none';
    entry.card.style.transform = at;
    entry.card.style.setProperty('--at', at);
    entry.card.style.opacity = slot.opacity;
    entry.card.style.zIndex = 10 - Math.abs(offset);
    entry.card.style.pointerEvents = slot === HIDDEN ? 'none' : '';
    if (wraps) { entry.card.getBoundingClientRect(); entry.card.style.transition = ''; }
    entry.offset = offset;
    entry.card.setAttribute('aria-checked', String(offset === 0));
    entry.card.tabIndex = offset === 0 ? 0 : -1;
  }
  const patron = cards[chosen].patron;
  $('patron-name').textContent = patron.name;
  $('catchphrase').textContent = `“${patron.catchphrase}”`;
  if (save) chrome.storage.sync.set({ patron: patron.slug });
}

$('prev').addEventListener('click', () => choose(chosen - 1));
$('next').addEventListener('click', () => choose(chosen + 1));
$('patrons').addEventListener('keydown', event => {
  const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key];
  if (!step) return;
  event.preventDefault();
  choose(chosen + step);
  cards[chosen].card.focus();
});

// Only the chosen patron idles; the rest hold their first frame.
(function animate(now) {
  const clip = LAYOUT.clips.idle;
  for (const [i, { card }] of cards.entries()) {
    const col = i === chosen ? frameIndex(clip, now) : 0;
    card.style.backgroundPosition = `${-col * LAYOUT.frameWidth * scale}px ${-clip.row * LAYOUT.frameHeight * scale}px`;
  }
  requestAnimationFrame(animate);
})(performance.now());

async function loadPatron() {
  const { patron = DEFAULT_PATRON } = await chrome.storage.sync.get('patron');
  renderPatrons();
  choose(Math.max(0, PATRONS.findIndex(p => p.slug === patron)), false);
}

loadSites();
loadPatron();
