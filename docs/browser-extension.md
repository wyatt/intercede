# Browser Extension: Page Dissolve — Blueprint

**Status:** decisions D1–D4 settled (recommendations adopted) · harness built · **Goal:** when the pet shows up on a distracting site, the page itself reacts — it holds still while he raises his hand, then dissolves into pixels as he sweeps it away.

The native app already knows *when* (budget breach → nudge) and *what site*. It can't touch page content, though: AppleScript can read a tab's URL but can't run an effect on the page. A browser extension can. This doc covers the effect, how the app and extension talk, and a phased build plan.

---

## Decisions (settled: recommendations adopted)

| # | Question | Decision |
|---|----------|----------------|
| D1 | **What's left after the dissolve?** (a) a calm "veil" over the page with a *Return anyway* button, (b) navigate the tab to a blank/new-tab page, (c) close the tab ("Insane mode") | **(a) by default**, (c) as an opt-in strict mode later. The veil can be undone and doesn't lose form input or scroll position, and a tab never vanishes without warning. |
| D2 | **When does the page react?** | Two beats, synced to the sprite: **on appearance** (raise-hand) the page *holds*: media pauses, the page dims slightly. **On the dismiss sweep** (golden pixels) it *dissolves*. The sweep is automatic, about 3 s after he starts speaking, so the page is dealt with before the user clicks him. A tap before then still sweeps first. *(Revised: originally the sweep waited for the tap.)* |
| D3 | **Which browsers first?** | **Chromium (Chrome, Arc, Brave, Edge)** — one MV3 codebase. Firefox next (same code, small manifest differences). Safari last: it needs an Xcode-built Safari Web Extension target, and Xcode isn't installed on this machine yet. |
| D4 | **Site permissions** | `<all_urls>` host permission (needed to inject on demand and to screenshot the tab). It's simple and right for a personal, unpacked install. Revisit with optional per-site permissions if it's ever published to the Chrome Web Store. |

---

## Architecture

```
┌──────────── FocusPet.app ─────────────┐        ┌────────── Browser ──────────┐
│ NudgeCoordinator                      │        │ background service worker   │
│   └─ NudgeScene (walkIn…dismiss…)     │        │   ├─ chrome.runtime          │
│        │ phase events                 │        │   │   .connectNative(...)    │
│        ▼                              │        │   └─ routes to active tab    │
│ BrowserBridge  (Unix socket server)   │        │            │                 │
│   ~/Library/Application Support/      │        │            ▼                 │
│   FocusPet/bridge.sock  (0600)        │        │ dissolve.js (injected into   │
└──────────────▲────────────────────────┘        │   the matching tab only)     │
               │ newline-delimited JSON          └────────────▲────────────────┘
┌──────────────┴────────────────────────┐                     │ stdio, 4-byte
│ FocusPetBridge  (tiny helper binary,  │◄────────────────────┘ length + JSON
│ Contents/Helpers/, launched BY the    │      (Native Messaging)
│ browser, one per browser profile)     │
└───────────────────────────────────────┘
```

### Why Native Messaging (and not a localhost WebSocket)

| | Native Messaging | Localhost WebSocket from the app |
|---|---|---|
| Who can connect | Only extension IDs listed in the host manifest | Any local process or web page; needs a token handshake |
| Keeping the MV3 service worker alive | An open `connectNative` port keeps it alive (Chrome 105+) | Worker is suspended after ~30s idle and drops the socket |
| Setup | App writes a small JSON manifest per browser | App opens a port (possible conflicts, firewall prompts) |
| Extra code | Helper binary that relays stdio ↔ socket | None |

The helper is ~100 lines and the security story is much better. **Native Messaging wins.**

**Helper vs. main binary:** the browser launches the host executable itself. Pointing it at the main `FocusPet` binary would start a second menu-bar app, so the host is a separate `FocusPetBridge` helper with no UI. It connects to the running app's socket; if the app isn't running, it tells the extension `{"type":"appUnavailable"}` and exits.

### Host manifest (written by the app on launch, idempotent)

```json
{
  "name": "com.focuspet.bridge",
  "description": "FocusPet browser bridge",
  "path": "/Users/<you>/Applications/FocusPet.app/Contents/Helpers/FocusPetBridge",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://<fixed-extension-id>/"]
}
```

| Browser | Manifest directory |
|---|---|
| Chrome | `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/` |
| Brave | `~/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts/` |
| Edge | `~/Library/Application Support/Microsoft Edge/NativeMessagingHosts/` |
| Arc | *verify* — Arc is Chromium-based but its host lookup path needs confirming |
| Firefox | `~/Library/Application Support/Mozilla/NativeMessagingHosts/` (uses `allowed_extensions`) |

The extension ID stays stable across unpacked reloads by pinning a public `key` in `manifest.json`.

---

## Message protocol (v1)

All messages are JSON with `type` and `v: 1`. The helper relays them unchanged in both directions.

**Extension → app**

| type | fields | when |
|---|---|---|
| `hello` | `browser`, `extensionVersion` | on connect; the app uses `browser` to route to the frontmost browser |
| `ack` | `nudgeId`, `ok`, `reason?` | after handling `hold`/`dissolve`; `ok:false` when no matching tab, a restricted page, etc. |
| `returnAnyway` | `nudgeId`, `host` | the user clicked *Return anyway* on the veil |

**App → extension**

| type | fields | when (sprite beat) |
|---|---|---|
| `hold` | `nudgeId`, `host` | `alert` starts (hand rises) |
| `dissolve` | `nudgeId`, `host`, `durationMs`, `petName`, `phrase` | `dismiss` starts (golden sweep) |
| `release` | `nudgeId` | nudge ended without a dissolve (e.g. replaced) — un-hold the page |

**Targeting rule:** act only on the **active tab of the focused window** whose host matches `host`, using the same normalization as `UsageTracker` (strip `www.`, subdomains match). Otherwise reply `ack ok:false` and do nothing. Background tabs and other sites are never touched.

---

## The dissolve effect (`dissolve.js`)

Injected on demand with `chrome.scripting.executeScript`, so it never runs on pages that aren't being nudged.

1. **Hold:** pause every `<video>`/`<audio>`. If the page is fullscreen, call `document.exitFullscreen()`. Fade in a 25% dim layer.
2. **Snapshot:** the background worker grabs the visible tab with `chrome.tabs.captureVisibleTab` and passes the image to the content script.
3. **Dissolve:** a full-viewport `<canvas>` inside a **closed Shadow DOM** host at `z-index: 2147483647`, so page CSS can't reach it. It draws the snapshot, then hides the real page underneath.
   - The snapshot is cut into **8×8 px tiles**, each with a random threshold biased by distance from the bottom-left (where the pet stands), so the dissolve sweeps away from his hand.
   - Tiles past their threshold drift up and fade. A few become **gold** (`#E8C15A`, matching his halo) and twinkle for ~300 ms: the "tiny golden pixels".
   - Duration ≈ the `dismiss` clip plus `settle` (~1.2 s), so the page is gone as he lowers his hand.
4. **Veil (D1a):** a calm parchment-coloured layer with the pet's catchphrase and phrase, plus a **Return anyway** button. That button removes the veil and sends `returnAnyway`; the app can log the override and start the normal 5-minute cooldown.

**Fallbacks:** if `captureVisibleTab` fails (some restricted pages, or a capture rate limit), `dissolve()` runs in **cover** mode: the same tile sweep, but veil-coloured tiles settle *over* the live page instead of page tiles drifting away. With `prefers-reduced-motion`, skip the particles and do a 300 ms fade.

**Known constraints:** content scripts can't run on `chrome://` pages, the Web Store, or PDF viewer tabs. Those get `ack ok:false` and the app shows the sprite only, as it does today. Cross-origin iframes don't matter, because we cover the top document.

---

## App-side changes (Swift)

- **`NudgeScene`** gets phase callbacks (`onPhase: (PetAnimation) -> Void`), fired from `play(_:)`. The coordinator maps `alert` → `hold` and `dismiss` → `dissolve`.
- **`BrowserBridge`** (new, `FocusPet/Bridge/`): an `NWListener` on a Unix socket at `~/Library/Application Support/FocusPet/bridge.sock` (mode 0600), tracking connected browsers by their `hello`. It sends to the bridge whose `browser` matches the frontmost app, and logs to `Log.bridge`.
- **`NativeHostInstaller`** (new): on launch, writes or updates the host manifest for each installed browser whose support directory exists. It rewrites the manifest whenever the app path changes.
- **`FocusPetBridge`** (new helper target): reads 4-byte little-endian length-prefixed JSON on stdin and writes newline JSON to the socket, and the reverse. Messages are capped at 1 MB (the Chrome limit for host→extension is 1 MB).
- **Without the extension:** everything stays as it is now. The bridge simply has no connections.

## Extension layout

```
Extension/
├── manifest.json        # MV3; permissions: nativeMessaging, scripting, tabs; host_permissions: <all_urls>; pinned "key"
├── src/background.js    # connectNative + reconnect with backoff; routing + targeting rule
├── src/dissolve.js      # ✅ hold / dissolve / veil, injected on demand (styles inlined into its shadow root)
└── dev/harness.html     # ✅ fake distracting site + controls to tune the effect with no app or extension
```

---

## Build plan

| Phase | Deliverable | Done when |
|---|---|---|
| **0** | Answer D1–D4 | ✅ recommendations adopted |
| **1** | `dev/harness.html` + `dissolve.js` ✅ built | The effect looks right in a plain page, including reduced-motion and the no-snapshot fallback |
| **2** | Extension + `FocusPetBridge` + `BrowserBridge`, Chrome only ✅ built | **Test Nudge** on a YouTube tab: page holds on raise-hand, dissolves on the sweep, veil appears; other tabs untouched; nothing breaks if the app isn't running |
| **3** | Brave / Edge / Arc manifests, Firefox port | Same check in each browser |
| **4** | Extension reports the active tab URL → `ActivityMonitor` prefers it over AppleScript/AX | Tracking works in Firefox, with no Automation prompt needed |
| **5** | Strict mode (close tab), Safari Web Extension | Needs Xcode for Safari |

**Testing**
- Swift unit tests for protocol encoding/decoding and the targeting rule (shared fixtures with JS).
- A small JS test for the length-prefix framing.
- The harness page for visual work.
- Manual end-to-end checks via Test Nudge.

## Risks

- **Arc's native-messaging path** is unconfirmed. If Arc doesn't support it, Arc users get sprite-only nudges.
- **`captureVisibleTab` rate limit** (about 2 calls/s) is fine for one nudge, but must not be called in a loop.
- **Browser updates** can break host lookup (paths moving). The installer should log what it wrote, and the popover could show a "browser extension connected" indicator next to the tracking status.

---

## Harness (phase 1)

Open `Extension/dev/harness.html` directly in Chrome (`file://` is fine). It's a fake video site with a real playing `<video>`, so you can check that hold pauses media.

- **Simulate nudge** (`N`): hold at 2.2 s (when the hand rises), dissolve 2 s later (the sweep), using the same timings as the app.
- **Hold** (`H`), **Dissolve** (`D`), and **Reset** (`R`) run each step on its own. While the veil is up it covers the control panel; use **Return anyway** or press `R`.
- **Mode:** *scatter* uses a page snapshot (the harness serializes its own DOM as a stand-in for `captureVisibleTab`); *cover* is the no-snapshot fallback.
- **Duration, Tile px, Gold %, Reduced motion** are tuning knobs, remembered in `localStorage`. Once they look right, copy them into `DEFAULTS` at the top of `dissolve.js`.

Checked in headless Chrome: media pauses on hold; scatter, cover, and reduced-motion all reach the veil; a second dissolve is refused; `release()` mid-effect cleans up; Return anyway (keyboard) fires `onReturn`; double injection is a no-op; no console errors.

## Phase 2 notes (as built)

- **Routing:** the app broadcasts every message to all connected helpers. Each extension acts only if one of its windows is focused and the active tab matches the host (for Test Nudge, which sends `test: true`: any http(s) tab in the last-focused window). This replaces the "route to the frontmost browser" idea.
- **Helper:** if the app isn't running, it keeps retrying the socket every 2 s and replays the extension's `hello` on connect. It also sends the extension `connected` / `appUnavailable`.
- **Debug overrides:** `FOCUSPET_BRIDGE_SOCKET` overrides the socket path for both the app and the helper.
- **Checked:** Swift tests cover line framing, the host installer, and a socket round-trip. End-to-end, a headless Chrome with the unpacked extension and the real helper against a stand-in app socket handled `hello`, `hold` (ack ok), and `dissolve` (ack ok, scatter mode).
