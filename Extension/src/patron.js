// Intercede patron overlay: the saint walks onto the page, raises a hand (the page holds), speaks,
// sweeps the page away (it dissolves), lowers his hand and waits; a click sends him off.
// Same beats and timings as the Mac app's NudgeScene.
//
// Injected on demand by the background worker after dissolve.js:
//   IntercedePatron.present({ sheetUrl, fontUrls, layout, name, catchphrase, phrase })
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
      font: 14px/1.3 "Intercede Read", ui-monospace, "SF Mono", Menlo, Consolas, monospace;
      -webkit-font-smoothing: none;
      opacity: 0; transform: scale(.8); transform-origin: bottom left;
      transition: opacity 250ms ease, transform 250ms cubic-bezier(.3, 1.4, .5, 1);
    }
    .bubble.on { opacity: 1; transform: none; }
    .bubble b { display: block; font: 13px/1.3 "Intercede Pixel", ui-monospace, Menlo, monospace; margin-bottom: 4px; }
  `;

  let active = null;

  function present(options) {
    loadFonts(options.fontUrls);
    active?.abort();
    active = new Scene(options);
    active.run();
  }

  class Scene {
    constructor({ sheetUrl, layout, name, catchphrase, phrase }) {
      this.layout = layout;
      this.words = { patronName: name, catchphrase, phrase };  // also shown on the veil
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
      // Snapshot the page without the patron in it, then dissolve; he stays above the veil.
      this.host.style.visibility = 'hidden';
      await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
      const snapshot = await chrome.runtime.sendMessage({ type: 'capture' }).catch(() => null);
      this.host.style.visibility = '';
      const done = IntercedeDissolve.dissolve({
        ...this.words,
        snapshot,
        durationMs: this.clipMs('dismiss') + 150 + this.clipMs('settle'),
        onReturn: () => chrome.runtime.sendMessage({ type: 'returnAnyway' }).catch(() => {}),
      });
      document.documentElement.append(this.host);
      await done;
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

  // The popup's pixel fonts, for the bubble. Fetched as data and added to the page's font set, so
  // the page's CSP (font-src) can't block them; the bubble falls back to monospace meanwhile.
  let fontsLoaded = false;
  async function loadFonts(urls = {}) {
    if (fontsLoaded) return;
    fontsLoaded = true;
    for (const [family, url] of Object.entries(urls)) {
      try {
        const face = new FontFace(family, await (await fetch(url)).arrayBuffer());
        document.fonts.add(await face.load());
      } catch { /* keep the fallback */ }
    }
  }

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text) node.textContent = text;  // never innerHTML
    return node;
  }

  globalThis.IntercedePatron = { present, get active() { return !!active; } };
})();
