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

const preview = $('preview');
const scale = 150 / LAYOUT.frameHeight;
let previewStart = performance.now();

function showPatron(slug) {
  const patron = patronFor(slug);
  $('catchphrase').textContent = `“${patron.catchphrase}”`;
  preview.setAttribute('aria-label', patron.name);
  preview.style.backgroundImage = `url("patrons/${patron.sheet}.png")`;
  preview.style.backgroundSize = `${LAYOUT.cols * LAYOUT.frameWidth * scale}px ${LAYOUT.rows * LAYOUT.frameHeight * scale}px`;
  previewStart = performance.now();
}

(function animate(now) {
  const clip = LAYOUT.clips.idle;
  const col = frameIndex(clip, now - previewStart);
  preview.style.backgroundPosition = `${-col * LAYOUT.frameWidth * scale}px ${-clip.row * LAYOUT.frameHeight * scale}px`;
  requestAnimationFrame(animate);
})(performance.now());

async function loadPatron() {
  const { patron = DEFAULT_PATRON } = await chrome.storage.sync.get('patron');
  const select = $('patron');
  select.replaceChildren(...PATRONS.map(p => new Option(p.name, p.slug, false, p.slug === patron)));
  showPatron(patron);
  select.addEventListener('change', () => {
    chrome.storage.sync.set({ patron: select.value });
    showPatron(select.value);
  });
}

loadSites();
loadPatron();
