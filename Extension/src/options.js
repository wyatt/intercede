// Settings page: tracked sites with daily limits, and the patron picker.
import { DEFAULT_SITES, addSite, removeSite, clampMinutes } from './tracker.js';
import { PATRONS, DEFAULT_PATRON, LAYOUT, patronFor, frameIndex } from './patrons.js';

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
      <button class="remove" type="button">Remove</button>`;
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

const SPRITE_HEIGHT = 100;
const scale = SPRITE_HEIGHT / LAYOUT.frameHeight;
const cards = new Map();  // slug → card button
let chosen = DEFAULT_PATRON;

function renderPatrons() {
  const grid = $('patrons');
  for (const patron of PATRONS) {
    const card = document.createElement('button');
    card.type = 'button';
    card.className = 'patron-card';
    card.setAttribute('role', 'radio');
    const sprite = document.createElement('div');
    sprite.className = 'sprite';
    sprite.style.backgroundImage = `url("patrons/${patron.sheet}.png")`;
    sprite.style.backgroundSize = `${LAYOUT.cols * LAYOUT.frameWidth * scale}px ${LAYOUT.rows * LAYOUT.frameHeight * scale}px`;
    card.append(sprite, document.createTextNode(patron.name));
    card.addEventListener('click', () => choose(patron.slug));
    cards.set(patron.slug, card);
    grid.append(card);
  }
}

function choose(slug, save = true) {
  chosen = patronFor(slug).slug;
  for (const [s, card] of cards) {
    card.setAttribute('aria-checked', String(s === chosen));
    card.tabIndex = s === chosen ? 0 : -1;
  }
  $('catchphrase').textContent = `“${patronFor(chosen).catchphrase}”`;
  if (save) chrome.storage.sync.set({ patron: chosen });
}

// Arrow keys move the choice, as in any radio group.
$('patrons').addEventListener('keydown', event => {
  const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key];
  if (!step) return;
  event.preventDefault();
  const slugs = PATRONS.map(p => p.slug);
  const next = slugs[(slugs.indexOf(chosen) + step + slugs.length) % slugs.length];
  choose(next);
  cards.get(next).focus();
});

// Every patron idles; only the chosen one keeps moving, the rest hold their first frame.
(function animate(now) {
  const clip = LAYOUT.clips.idle;
  for (const [slug, card] of cards) {
    const col = slug === chosen ? frameIndex(clip, now) : 0;
    card.firstChild.style.backgroundPosition = `${-col * LAYOUT.frameWidth * scale}px ${-clip.row * LAYOUT.frameHeight * scale}px`;
  }
  requestAnimationFrame(animate);
})(performance.now());

async function loadPatron() {
  const { patron = DEFAULT_PATRON } = await chrome.storage.sync.get('patron');
  renderPatrons();
  choose(patron, false);
}

loadSites();
loadPatron();
