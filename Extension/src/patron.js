// Intercede patron overlay: the saint walks onto the page, raises a hand (the page holds), speaks,
// sweeps the page away (it dissolves), lowers his hand and waits; a click sends him off.
// The beats: walk in, hold, speak, sweep, settle, and walk out when clicked.
//
// Injected on demand by the background worker after dissolve.js:
//   IntercedePatron.present({ sheetUrl, layout, name, catchphrase, phrase, host, returnDelayS?, dissolve? })
(() => {
  if (globalThis.IntercedePatron) return;

  const Z = 2147483647;
  const SPRITE_HEIGHT = 150;
  const REST_X = 0, BOTTOM = 8;  // his frame has ~22px of transparent margin, so the figure stands ~22px in
  const WALK_MS = 1600, IDLE_MS = 600, SPEAK_BEFORE_SWEEP_MS = 1500, AUTO_DISMISS_MS = 45000;

  const STYLE = `
    :host { all: initial; }
    .stage { position: fixed; left: 0; bottom: 0; width: 100vw; height: 100vh; pointer-events: none; }
    .sprite {
      position: absolute; left: 0; bottom: ${BOTTOM}px; pointer-events: auto; cursor: pointer;
      background-repeat: no-repeat; transition-property: transform; transition-timing-function: linear;
    }
    .bubble {
      position: absolute; bottom: ${BOTTOM + SPRITE_HEIGHT + 4}px; max-width: 340px; box-sizing: border-box;
      padding: 8px 12px; background: #fff; color: #000; border: 2px solid #000; border-radius: 8px;
      box-shadow: 2px 2px 4px rgba(0,0,0,.2); pointer-events: auto; cursor: pointer;
      font: 500 12px/1.4 ui-monospace, "SF Mono", Menlo, "Cascadia Mono", Consolas, monospace;
      opacity: 0; transform: scale(.8); transform-origin: bottom left;
      transition: opacity 250ms ease, transform 250ms cubic-bezier(.3, 1.4, .5, 1);
    }
    .bubble.on { opacity: 1; transform: none; }
    .bubble b { display: block; font-size: 14px; font-weight: 700; margin-bottom: 4px; }
  `;

  let active = null;

  function present(options) {
    active?.abort();
    active = new Scene(options);
    active.run();
  }

  class Scene {
    constructor({ sheetUrl, layout, name, catchphrase, phrase, host, returnDelayS, dissolve }) {
      this.layout = layout;
      this.siteHost = host;  // the tracked site he came about (null for a test)
      this.words = { patronName: name, catchphrase, phrase };  // also shown on the veil
      this.returnDelayS = returnDelayS;  // undefined: the dissolve's default
      this.dissolveOptions = dissolve;   // e.g. coarser tiles for the landing page's scaled-down demo
      this.scale = SPRITE_HEIGHT / layout.frameHeight;
      this.width = Math.round(layout.frameWidth * this.scale);
      this.offstage = -this.width - 20;
      this.cancelled = false;
      this.exiting = false;
      this.swept = false;
      this.held = false;

      this.host = document.createElement('intercede-patron');
      this.host.style.cssText = `position:fixed;inset:0;z-index:${Z};pointer-events:none;`;
      const root = this.host.attachShadow({ mode: 'closed' });
      const style = document.createElement('style');
      style.textContent = STYLE;
      const stage = el('div', 'stage');

      this.sprite = el('div', 'sprite');
      this.sprite.setAttribute('role', 'img');
      this.sprite.setAttribute('aria-label', name);
      Object.assign(this.sprite.style, {
        width: `${this.width}px`,
        height: `${SPRITE_HEIGHT}px`,
        backgroundImage: `url("${sheetUrl}")`,
        backgroundSize: `${layout.cols * layout.frameWidth * this.scale}px ${layout.rows * layout.frameHeight * this.scale}px`,
      });

      this.sheet = new Image();  // for cutting his silhouette out of the snapshot
      this.sheet.src = sheetUrl;

      this.bubble = el('div', 'bubble');
      this.bubble.append(el('b', '', catchphrase), document.createTextNode(phrase));

      for (const target of [this.sprite, this.bubble]) target.addEventListener('click', () => this.exit());
      stage.append(this.bubble, this.sprite);
      root.append(style, stage);
      document.documentElement.append(this.host);

      this.moveTo(this.offstage, 0);
      this.play('walkIn');
      this.frame = requestAnimationFrame(this.tick);
    }

    // ── Choreography ──

    async run() {
      // A clean picture of the page before he arrives, to patch over him in the later snapshot.
      this.clean = await capture();
      if (this.cancelled) return;
      // Commit the offstage position before starting the walk; otherwise the browser merges both
      // style changes and he appears already standing there, with no walk-in.
      this.sprite.getBoundingClientRect();
      this.moveTo(REST_X, WALK_MS);
      if (!await this.wait(WALK_MS)) return;
      this.play('idle');
      if (!await this.wait(IDLE_MS)) return;
      this.play('alert');
      this.hold();
      if (!await this.wait(this.clipMs('alert'))) return;
      this.play('talk');
      this.bubble.classList.add('on');
      if (!await this.wait(SPEAK_BEFORE_SWEEP_MS)) return;
      if (!await this.sweep()) return;
      this.play('idle');  // hand lowered, bubble still up, until clicked
      if (!await this.wait(AUTO_DISMISS_MS)) return;
      this.exit();
    }

    /** The dismiss gesture (the page dissolves on it), then lowering his hand. */
    async sweep() {
      this.swept = true;
      this.play('dismiss');
      this.dissolvePage();
      if (!await this.wait(this.clipMs('dismiss') + 150)) return false;
      this.play('settle');
      return this.wait(this.clipMs('settle'));
    }

    async exit() {
      if (this.exiting) return;
      this.exiting = true;
      const pendingSweep = !this.swept && (this.clip === 'alert' || this.clip === 'talk');
      // Any new wait() supersedes the one run() is blocked on, so run() stops at its next step.
      this.bubble.classList.remove('on');
      if (pendingSweep) await this.sweep();
      else if (this.clip === 'dismiss') { this.play('settle'); await this.wait(this.clipMs('settle')); }
      else if (this.held && !this.swept) IntercedeDissolve.release();
      this.play('walkOut');
      this.moveTo(this.offstage, WALK_MS);
      await this.wait(WALK_MS);
      this.remove();
    }

    abort() {
      this.cancelled = true;
      if (this.held && !this.swept) IntercedeDissolve.release();
      this.remove();
    }

    remove() {
      cancelAnimationFrame(this.frame);
      this.host.remove();
      if (active === this) active = null;
      chrome.runtime.sendMessage({ type: 'patronDone' }).catch(() => {});
    }

    // ── The page ──

    hold() {
      this.held = true;
      IntercedeDissolve.hold();
      document.documentElement.append(this.host);  // stay above the dim layer
    }

    async dissolvePage() {
      // Snapshot the page with him on it (hiding him would flash), then patch his figure and the
      // bubble with the clean picture, so no copy of him breaks apart; he stays above the veil.
      this.frozen = true;  // hold his frame still so the patch matches the snapshot exactly
      const [shot, clean] = await Promise.all([capture().then(loadImage), loadImage(this.clean)]);
      const at = this.sprite.getBoundingClientRect();
      const snapshot = shot && clean ? this.withoutHim(shot, clean, at) : null;
      this.frozen = false;
      const done = IntercedeDissolve.dissolve({
        ...this.words,
        ...(this.returnDelayS !== undefined && { returnDelayS: this.returnDelayS }),
        ...this.dissolveOptions,
        snapshot,
        origin: { x: at.x + at.width * 0.7, y: at.y + at.height * 0.35 },  // his raised hand
        durationMs: this.clipMs('dismiss') + 150 + this.clipMs('settle') + 700,
        onReturn: () => chrome.runtime.sendMessage({ type: 'returnAnyway', host: this.siteHost }).catch(() => {}),
      });
      document.documentElement.append(this.host);
      await done;
    }

    /** `shot` with his figure and the bubble replaced by the same pixels of `clean`, dimmed to match. */
    withoutHim(shot, clean, at) {
      const W = innerWidth, H = innerHeight, dpr = shot.naturalWidth / W;
      const out = canvas(shot.naturalWidth, shot.naturalHeight), o = out.getContext('2d');
      const patch = canvas(out.width, out.height), p = patch.getContext('2d');
      o.drawImage(shot, 0, 0);
      p.scale(dpr, dpr);
      // Mask: his current frame, grown by a couple of pixels, and the bubble with its shadow.
      const { frameWidth: fw, frameHeight: fh } = this.layout;
      for (const [dx, dy] of [[-2, 0], [2, 0], [0, -2], [0, 2], [0, 0]]) {
        p.drawImage(this.sheet, this.col * fw, this.row * fh, fw, fh, at.x + dx, at.y + dy, at.width, at.height);
      }
      const b = this.bubble.getBoundingClientRect();
      if (b.width && getComputedStyle(this.bubble).opacity !== '0') p.fillRect(b.x - 4, b.y - 4, b.width + 10, b.height + 10);
      p.globalCompositeOperation = 'source-in';
      p.drawImage(clean, 0, 0, W, H);
      p.globalCompositeOperation = 'source-atop';
      p.fillStyle = IntercedeDissolve.dimColor;  // the hold's dim, which the clean picture predates
      p.fillRect(0, 0, W, H);
      o.drawImage(patch, 0, 0);
      return out;
    }

    // ── Animation ──

    play(clip) {
      this.clip = clip;
      this.clipStart = performance.now();
    }

    clipMs(name) {
      const c = this.layout.clips[name];
      return (c.frames / c.fps) * 1000;
    }

    tick = now => {
      const c = this.layout.clips[this.clip];
      const n = Math.max(0, Math.floor(((now - this.clipStart) / 1000) * c.fps));
      const col = c.loops ? n % c.frames : Math.min(n, c.frames - 1);
      if (this.frozen) { this.frame = requestAnimationFrame(this.tick); return; }
      this.col = col; this.row = c.row;
      const fw = this.layout.frameWidth * this.scale, fh = this.layout.frameHeight * this.scale;
      this.sprite.style.backgroundPosition = `${-col * fw}px ${-c.row * fh}px`;
      this.frame = requestAnimationFrame(this.tick);
    };

    moveTo(x, ms) {
      this.sprite.style.transitionDuration = `${ms}ms`;
      this.sprite.style.transform = `translateX(${x}px)`;
      this.bubble.style.left = `${REST_X + this.width * 0.45}px`;
    }

    /** Resolves false if the scene was cancelled meanwhile. */
    wait(ms) {
      const token = this.token = (this.token ?? 0) + 1;
      return new Promise(resolve => setTimeout(() => resolve(!this.cancelled && token === this.token), ms));
    }
  }

  const capture = () => chrome.runtime.sendMessage({ type: 'capture' }).catch(() => null);

  async function loadImage(src) {
    if (!src) return null;
    const img = new Image();
    img.src = src;
    try { await img.decode(); return img; } catch { return null; }
  }

  function canvas(w, h) {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    return c;
  }

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text) node.textContent = text;  // never innerHTML
    return node;
  }

  globalThis.IntercedePatron = { present, get active() { return !!active; } };
})();
