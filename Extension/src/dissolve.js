// Intercede page dissolve: hold → dissolve → veil.
//
// Injected on demand by the extension's background worker (chrome.scripting.executeScript) into
// the one tab being nudged, and loaded directly by dev/harness.html for tuning. Everything lives in
// a closed shadow root at the top z-index so the page's CSS can't reach it.
//
//   IntercedeDissolve.hold()                 media pauses, page dims (patron raises his hand)
//   await IntercedeDissolve.dissolve({...})  page breaks into pixels and drifts away (his sweep)
//   IntercedeDissolve.release()              remove everything (no-op if nothing is showing)
(() => {
  if (globalThis.IntercedeDissolve) return;  // injected twice into the same page

  const Z = 2147483647;
  const DEFAULTS = {
    durationMs: 1200,     // ≈ the patron's dismiss + settle clips
    tileSize: 8,          // CSS px
    goldFraction: 0.05,   // share of tiles that become golden sparkles
    tileLife: 0.45,       // fraction of the duration each tile spends flying away
    origin: null,         // {x, y} the burst comes from (his raised hand); default bottom-left
    returnDelayS: 10,     // "Return anyway" stays locked this long (counted only while the tab is visible)
  };
  const GOLD = '#E8C15A';
  const VEIL = '#F4ECD8';
  const SPECKS = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='1440' height='1440' fill='%23EBE0C3'%3E%3Crect x='48' y='96' width='48' height='48'/%3E%3Crect x='144' y='528' width='48' height='48'/%3E%3Crect x='288' y='48' width='48' height='48'/%3E%3Crect x='480' y='192' width='48' height='48'/%3E%3Crect x='576' y='960' width='48' height='48'/%3E%3Crect x='864' y='48' width='48' height='48'/%3E%3Crect x='1248' y='816' width='48' height='48'/%3E%3Crect x='1392' y='768' width='48' height='48'/%3E%3C/svg%3E";  // big, faint, darker pixels scattered on the veil
  const DIM = 'rgba(24, 12, 32, 0.28)';
  const GRAVITY = 1100;   // px/s², for the tossed tiles
  const FLASH_MS = 260;
  const SHAKE_MS = 200;

  const STYLE = `
    :host { all: initial; }
    .layer { position: fixed; inset: 0; }
    .dim { background: ${DIM}; opacity: 0; transition: opacity 400ms ease; pointer-events: none; }
    .dim.on { opacity: 1; }
    canvas { position: fixed; inset: 0; width: 100vw; height: 100vh; pointer-events: none; }
    .veil {
      background: ${VEIL} url("${SPECKS}") 0 0 / 1440px 1440px; display: flex; align-items: center; justify-content: center;
      font: 500 15px/1.45 ui-monospace, "SF Mono", Menlo, Consolas, monospace; color: #3B2A1A;
    }
    .card { max-width: 30em; padding: 2em; text-align: center; opacity: 0; transform: translateY(6px);
            transition: opacity 500ms ease, transform 500ms ease; }
    .card.on { opacity: 1; transform: none; }
    .catchphrase { font-size: 1.5em; font-weight: 700; margin: 0 0 0.6em; }
    .phrase { margin: 0 0 0.4em; }
    .patron { margin: 0 0 1.8em; color: #8A6A3A; font-size: 0.85em; }
    .patron::before { content: "— "; }
    button {
      font: inherit; font-size: 0.85em; color: #3B2A1A; background: transparent; cursor: pointer;
      border: 2px solid #3B2A1A; border-radius: 6px; padding: 0.45em 1.1em;
    }
    button:hover { background: ${GOLD}; }
    button { position: relative; overflow: hidden; font-variant-numeric: tabular-nums; }
    button .fill { position: absolute; inset: 0 auto 0 0; width: 0; background: ${GOLD}; opacity: .45;
                   transition: width 1s steps(4); }
    button .label { position: relative; }
    button[aria-disabled="true"] { cursor: default; color: #8A6A3A; border-color: #8A6A3A; }
    button[aria-disabled="true"]:hover { background: transparent; }
    button:focus-visible { outline: 3px solid ${GOLD}; outline-offset: 2px; }
  `;

  let host = null, root = null, dim = null;
  let state = 'idle';          // idle | held | dissolving | veiled
  let frame = 0;
  let finish = null;           // resolves the in-flight dissolve() promise
  let countdown = 0;           // interval locking the "Return anyway" button

  function ensureHost() {
    if (host) return;
    host = document.createElement('intercede-dissolve');
    host.style.cssText = `position:fixed;inset:0;z-index:${Z};pointer-events:none;`;
    root = host.attachShadow({ mode: 'closed' });
    const style = document.createElement('style');
    style.textContent = STYLE;
    root.append(style);
    document.documentElement.append(host);
  }

  function hold() {
    if (state !== 'idle') return { paused: 0 };
    ensureHost();
    let paused = 0;
    for (const media of document.querySelectorAll('video, audio')) {
      if (!media.paused) { media.pause(); paused++; }
    }
    if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
    dim = el('div', 'layer dim');
    root.append(dim);
    requestAnimationFrame(() => dim && dim.classList.add('on'));
    state = 'held';
    return { paused };
  }

  async function dissolve(options = {}) {
    const opts = { ...DEFAULTS, ...options };
    if (state === 'dissolving' || state === 'veiled') return { ok: false, reason: 'already ' + state };
    hold();
    host.style.pointerEvents = 'auto';  // the page underneath is no longer interactive
    state = 'dissolving';

    const snapshot = await loadSnapshot(opts.snapshot);
    if (state !== 'dissolving') return { ok: false, reason: 'released' };
    const veil = buildVeil(opts);
    root.append(veil.layer);

    const reduced = opts.reducedMotion ?? matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduced) await fadeOut(snapshot, veil);
    else await animateTiles(snapshot, veil, opts);
    if (state !== 'dissolving') return { ok: false, reason: 'released' };  // release() mid-effect

    dim?.remove(); dim = null;
    veil.layer.style.opacity = '1';
    veil.card.classList.add('on');
    veil.button.focus({ preventScroll: true });
    lockReturn(veil.button, opts.returnDelayS);
    state = 'veiled';
    return { ok: true, mode: snapshot ? 'scatter' : 'cover', reduced };
  }

  function release() {
    cancelAnimationFrame(frame);
    clearInterval(countdown); countdown = 0;
    finish?.(); finish = null;
    host?.remove();
    host = root = dim = null;
    state = 'idle';
  }

  // ── Effect ────────────────────────────────────────────────────────────────

  // Two modes share one tile schedule:
  //   scatter: with a snapshot of the page, tiles of it drift away and reveal the veil beneath.
  //   cover:   without one (capture failed), veil-coloured tiles settle over the live page.
  function animateTiles(snapshot, veil, opts) {
    const dpr = window.devicePixelRatio || 1;
    const W = innerWidth, H = innerHeight;
    const t = opts.tileSize;
    const base = canvas(W, H, dpr);      // the snapshot (scatter) or the growing veil (cover)
    const fx = canvas(W, H, dpr);        // tiles in flight
    const b = base.getContext('2d'), f = fx.getContext('2d');
    b.scale(dpr, dpr); f.scale(dpr, dpr);
    b.imageSmoothingEnabled = f.imageSmoothingEnabled = false;

    const scatter = !!snapshot;
    if (scatter) {
      b.drawImage(snapshot, 0, 0, W, H);
    } else {
      veil.layer.style.opacity = '0';    // live page stays visible until the tiles cover it
    }
    root.append(base, fx);

    const sx = scatter ? (snapshot.naturalWidth || snapshot.width) / W : 0;
    const sy = scatter ? (snapshot.naturalHeight || snapshot.height) / H : 0;
    const origin = opts.origin ?? { x: 0, y: H };
    const reach = Math.max(...[[0, 0], [W, 0], [0, H], [W, H]].map(([x, y]) => Math.hypot(x - origin.x, y - origin.y)));
    const tiles = schedule(W, H, t, opts, origin, reach);
    let next = 0;
    const live = [];
    const start = performance.now();

    return new Promise(resolve => {
      finish = resolve;
      const step = now => {
        const elapsed = now - start, p = elapsed / opts.durationMs;
        // A jolt as his hand comes down.
        base.style.transform = elapsed < SHAKE_MS
          ? `translate(${Math.round((Math.random() - 0.5) * 6)}px, ${Math.round((Math.random() - 0.5) * 6)}px)` : '';
        while (next < tiles.length && tiles[next].start <= p) {
          const tile = tiles[next++];
          if (scatter) b.clearRect(tile.x, tile.y, t, t);
          live.push(tile);
        }

        f.clearRect(0, 0, W, H);
        for (let i = live.length - 1; i >= 0; i--) {
          const tile = live[i];
          const q = (p - tile.start) / tile.life;
          if (q >= 1) {
            if (!scatter) { b.fillStyle = VEIL; b.fillRect(tile.x, tile.y, t, t); }
            live.splice(i, 1);
            continue;
          }
          if (scatter) drawTossed(f, tile, q * tile.life * opts.durationMs / 1000, q, t, snapshot, sx, sy, dpr);
          else drawSettling(f, tile, q, t);
        }
        f.setTransform(dpr, 0, 0, dpr, 0, 0);
        drawShockwave(f, origin, reach, p, W, H);
        drawFlash(f, origin, elapsed);

        if (next < tiles.length || live.length) {
          frame = requestAnimationFrame(step);
        } else {
          base.remove(); fx.remove();
          finish = null;
          resolve();
        }
      };
      frame = requestAnimationFrame(step);
    });
  }

  // Tiles burst away from his hand in a widening ring (with some noise), tossed up and outwards
  // to tumble off under gravity; the gold ones float up, twinkling.
  function schedule(W, H, t, opts, origin, reach) {
    const tiles = [];
    for (let y = 0; y < H; y += t) {
      for (let x = 0; x < W; x += t) {
        const cx = x + t / 2 - origin.x, cy = y + t / 2 - origin.y;
        const d = Math.hypot(cx, cy) || 1;
        const life = opts.tileLife * (0.7 + Math.random() * 0.6);
        const start = Math.min((d / reach) * 0.62 + Math.random() * 0.15, 1 - life);
        const gold = Math.random() < opts.goldFraction;
        const speed = 120 + Math.random() * 260;
        tiles.push({
          x, y, start, life, gold,
          vx: gold ? (Math.random() - 0.5) * 40 : (cx / d) * speed + (Math.random() - 0.5) * 60,
          vy: gold ? -(60 + Math.random() * 120) : (cy / d) * speed - (150 + Math.random() * 250),
          spin: (Math.random() - 0.5) * 14,  // rad/s
        });
      }
    }
    return tiles.sort((a, b) => a.start - b.start);
  }

  // `s` is the tile's age in seconds, `q` the fraction of its life gone.
  function drawTossed(f, tile, s, q, t, snapshot, sx, sy, dpr) {
    const fall = tile.gold ? 0 : 0.5 * GRAVITY * s * s;
    const x = tile.x + t / 2 + tile.vx * s, y = tile.y + t / 2 + tile.vy * s + fall;
    const size = t * (1 - 0.3 * q);
    const a = tile.spin * s, c = Math.cos(a) * dpr, n = Math.sin(a) * dpr;
    f.setTransform(c, n, -n, c, x * dpr, y * dpr);
    if (tile.gold) {
      // Twinkling golden star, echoing the sparkles in the patron's dismiss animation.
      f.globalAlpha = (1 - q) * (0.6 + 0.4 * Math.sin(q * 30));
      f.fillStyle = GOLD;
      const arm = size / 3;
      f.fillRect(-arm / 2, -size / 2 - arm, arm, size + 2 * arm);
      f.fillRect(-size / 2 - arm, -arm / 2, size + 2 * arm, arm);
    } else {
      f.globalAlpha = q < 0.6 ? 1 : (1 - q) / 0.4;
      f.drawImage(snapshot, tile.x * sx, tile.y * sy, t * sx, t * sy, -size / 2, -size / 2, size, size);
    }
    f.globalAlpha = 1;
  }

  // A ring of gold pixels racing outwards from his hand, just ahead of the breaking edge.
  function drawShockwave(f, origin, reach, p, W, H) {
    const life = 0.7;
    if (p >= life) return;
    const r = (p / 0.62) * reach + 12;
    f.globalAlpha = 1 - p / life;
    f.fillStyle = GOLD;
    const dots = Math.max(8, Math.floor((2 * Math.PI * r) / 14));
    for (let i = 0; i < dots; i++) {
      const a = (i / dots) * 2 * Math.PI;
      const x = origin.x + Math.cos(a) * r, y = origin.y + Math.sin(a) * r;
      if (x > -4 && x < W && y > -4 && y < H) f.fillRect(Math.round(x / 2) * 2, Math.round(y / 2) * 2, 4, 4);
    }
    f.globalAlpha = 1;
  }

  // A brief pixel starburst at his hand.
  function drawFlash(f, origin, elapsed) {
    if (elapsed >= FLASH_MS) return;
    const k = elapsed / FLASH_MS;
    f.globalAlpha = 1 - k;
    for (let ray = 0; ray < 8; ray++) {
      const a = (ray / 8) * 2 * Math.PI;
      for (let step = 1; step <= 5; step++) {
        const dist = step * (6 + k * 18);
        f.fillStyle = step % 2 ? '#FFFFFF' : GOLD;
        f.fillRect(Math.round(origin.x + Math.cos(a) * dist) - 2, Math.round(origin.y + Math.sin(a) * dist) - 2, 4, 4);
      }
    }
    f.fillStyle = '#FFFFFF';
    f.fillRect(origin.x - 5, origin.y - 5, 10, 10);
    f.globalAlpha = 1;
  }

  function drawSettling(f, tile, q, t) {
    f.globalAlpha = q;
    f.fillStyle = tile.gold && q < 0.7 ? GOLD : VEIL;
    f.fillRect(tile.x, tile.y - (1 - q) * 18, t, t);
    f.globalAlpha = 1;
  }

  // prefers-reduced-motion: no particles, just a short crossfade to the veil.
  function fadeOut(snapshot, veil) {
    const W = innerWidth, H = innerHeight, dpr = window.devicePixelRatio || 1;
    const c = canvas(W, H, dpr);
    if (snapshot) {
      const g = c.getContext('2d'); g.scale(dpr, dpr); g.drawImage(snapshot, 0, 0, W, H);
      root.append(c);
    } else {
      veil.layer.style.opacity = '0';
    }
    c.style.transition = veil.layer.style.transition = 'opacity 300ms ease';
    return new Promise(resolve => {
      finish = resolve;
      requestAnimationFrame(() => { c.style.opacity = '0'; veil.layer.style.opacity = '1'; });
      setTimeout(() => { c.remove(); finish = null; resolve(); }, 320);
    });
  }

  // ── DOM helpers ───────────────────────────────────────────────────────────

  function buildVeil(opts) {
    const layer = el('div', 'layer veil');
    const card = el('div', 'card');
    card.setAttribute('role', 'dialog');
    card.setAttribute('aria-label', 'Page dismissed by your patron');
    if (opts.catchphrase) card.append(el('p', 'catchphrase', opts.catchphrase));
    if (opts.phrase) card.append(el('p', 'phrase', opts.phrase));
    if (opts.patronName) card.append(el('p', 'patron', opts.patronName));
    const button = el('button');
    button.append(el('span', 'fill'), el('span', 'label', 'Return anyway'));
    button.addEventListener('click', () => {
      if (button.getAttribute('aria-disabled') === 'true') return;
      release();
      opts.onReturn?.();
    });
    card.append(button);
    layer.append(card);
    return { layer, card, button };
  }

  // Keeps the button locked for `seconds`, counting down on it; time in a hidden tab doesn't count.
  function lockReturn(button, seconds) {
    if (!(seconds > 0)) return;
    const total = Math.ceil(seconds);
    let left = total;
    const label = button.querySelector('.label'), fill = button.querySelector('.fill');
    const show = () => {
      label.textContent = `Return anyway in ${left}`;
      fill.style.width = `${((total - left) / total) * 100}%`;
    };
    button.setAttribute('aria-disabled', 'true');
    show();
    countdown = setInterval(() => {
      if (document.hidden) return;
      if (--left > 0) return show();
      clearInterval(countdown); countdown = 0;
      button.removeAttribute('aria-disabled');
      fill.remove();
      label.textContent = 'Return anyway';
    }, 1000);
  }

  function canvas(W, H, dpr) {
    const c = document.createElement('canvas');
    c.width = Math.round(W * dpr);
    c.height = Math.round(H * dpr);
    return c;
  }

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text) node.textContent = text;  // never innerHTML: phrases come from outside the page
    return node;
  }

  // Accepts an image/canvas/bitmap, a data/blob URL (what captureVisibleTab returns), or nothing.
  async function loadSnapshot(src) {
    if (!src) return null;
    if (typeof src !== 'string') return src;
    const img = new Image();
    img.src = src;
    try { await img.decode(); return img; } catch { return null; }  // fall back to cover mode
  }

  globalThis.IntercedeDissolve = {
    hold, dissolve, release,
    get state() { return state; },
    defaults: { ...DEFAULTS },
    dimColor: DIM,
  };
})();
