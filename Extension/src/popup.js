// Toolbar popup: today's time per tracked site against its budget, the patron, and Test Nudge.
import { DEFAULT_SITES, dayKey, normalizeHost } from './tracker.js';
import { DEFAULT_PATRON, LAYOUT, patronFor, frameIndex } from './patrons.js';

const $ = id => document.getElementById(id);

function formatTime(seconds) {
  const total = Math.floor(seconds);
  const h = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60), s = total % 60;
  if (h) return `${h}h ${m}m`;
  if (m) return `${m}m ${s}s`;
  return `${s}s`;
}

async function render() {
  const { sites = DEFAULT_SITES, patron = DEFAULT_PATRON } = await chrome.storage.sync.get(['sites', 'patron']);
  const key = `usage:${dayKey(new Date())}`;
  const usage = (await chrome.storage.local.get(key))[key] ?? {};

  showPatron(patronFor(patron));
  const stats = $('stats');
  stats.replaceChildren();
  if (!sites.length) {
    stats.append(Object.assign(document.createElement('p'), { className: 'muted', textContent: 'No sites tracked yet.' }));
    return;
  }
  for (const site of sites) {
    const used = usage[normalizeHost(site.host)] ?? 0;
    const over = used >= site.dailyBudgetSeconds;
    const row = document.createElement('div');
    row.className = 'site';
    row.innerHTML = `
      <div class="site-head">
        <span class="host"></span>
        <span class="used${over ? ' over' : ''}"></span>
        <span class="muted"></span>
      </div>
      <div class="bar"><div${over ? ' class="over"' : ''}></div></div>`;
    row.querySelector('.host').textContent = site.host;
    row.querySelector('.used').textContent = formatTime(used);
    row.querySelector('.muted').textContent = `/ ${formatTime(site.dailyBudgetSeconds)}`;
    row.querySelector('.bar > div').style.width = `${Math.min(used / Math.max(site.dailyBudgetSeconds, 1), 1) * 100}%`;
    stats.append(row);
  }
}

// The patron idles in the footer.
const sprite = $('sprite');
const scale = 48 / LAYOUT.frameHeight;

function showPatron(patron) {
  $('patron').textContent = patron.name;
  sprite.setAttribute('aria-label', patron.name);
  sprite.style.backgroundImage = `url("patrons/${patron.sheet}.png")`;
  sprite.style.backgroundSize = `${LAYOUT.cols * LAYOUT.frameWidth * scale}px ${LAYOUT.rows * LAYOUT.frameHeight * scale}px`;
}

(function animate(now) {
  const clip = LAYOUT.clips.idle;
  sprite.style.backgroundPosition = `${-frameIndex(clip, now) * LAYOUT.frameWidth * scale}px ${-clip.row * LAYOUT.frameHeight * scale}px`;
  requestAnimationFrame(animate);
})(performance.now());

$('settings').addEventListener('click', () => chrome.runtime.openOptionsPage());
$('test').addEventListener('click', async () => {
  await chrome.runtime.sendMessage({ type: 'testNudge' });
  window.close();
});
chrome.storage.onChanged.addListener(render);
chrome.runtime.sendMessage({ type: 'flush' }).catch(() => {});
render();
