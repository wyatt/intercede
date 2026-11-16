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
    tileLife: 0.35,       // fraction of the duration each tile spends drifting away
    returnDelayS: 10,     // "Return anyway" stays locked this long (counted only while the tab is visible)
  };
  const GOLD = '#E8C15A';
  const VEIL = '#F4ECD8';

  const STYLE = `
    :host { all: initial; }
    .layer { position: fixed; inset: 0; }
    .dim { background: rgba(24, 12, 32, 0.28); opacity: 0; transition: opacity 400ms ease; pointer-events: none; }
    .dim.on { opacity: 1; }
    canvas { position: fixed; inset: 0; width: 100vw; height: 100vh; pointer-events: none; }
    .veil {
      background: ${VEIL}; display: flex; align-items: center; justify-content: center;
      font: 16px/1.45 -apple-system, system-ui, "Helvetica Neue", sans-serif; color: #3B2A1A;
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
    const tiles = schedule(W, H, t, opts);
    let next = 0;
    const live = [];
    const start = performance.now();

    return new Promise(resolve => {
      finish = resolve;
      const step = now => {
        const p = (now - start) / opts.durationMs;
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
          if (scatter) drawDrifting(f, tile, q, t, snapshot, sx, sy);
          else drawSettling(f, tile, q, t);
        }

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

  // Tiles leave in a sweep away from the bottom-left, where the patron stands, with some noise.
  function schedule(W, H, t, opts) {
    const diag = Math.hypot(W, H);
    const tiles = [];
    for (let y = 0; y < H; y += t) {
      for (let x = 0; x < W; x += t) {
        const d = Math.hypot(x + t / 2, H - (y + t / 2)) / diag;
        const life = opts.tileLife * (0.7 + Math.random() * 0.6);
        const start = Math.min(d * 0.62 + Math.random() * 0.22, 1 - life);
        tiles.push({
          x, y, start, life,
          gold: Math.random() < opts.goldFraction,
          dx: 12 + Math.random() * 36,     // drift right…
          dy: -(30 + Math.random() * 70),  // …and up, away from his hand
        });
      }
    }
    return tiles.sort((a, b) => a.start - b.start);
  }

  function drawDrifting(f, tile, q, t, snapshot, sx, sy) {
    const ease = q * q;
    const x = tile.x + tile.dx * ease, y = tile.y + tile.dy * ease;
    const size = t * (1 - 0.45 * q);
    const inset = (t - size) / 2;
    if (tile.gold) {
      // Twinkling golden pixel, echoing the sparkles in the patron's dismiss animation.
      f.globalAlpha = (1 - q) * (0.65 + 0.35 * Math.sin(q * 24));
      f.fillStyle = GOLD;
      const arm = size / 3;
      f.fillRect(x + inset + arm, y + inset, arm, size);
      f.fillRect(x + inset, y + inset + arm, size, arm);
    } else {
      f.globalAlpha = 1 - q;
      f.drawImage(snapshot, tile.x * sx, tile.y * sy, t * sx, t * sy, x + inset, y + inset, size, size);
    }
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
  };
})();
