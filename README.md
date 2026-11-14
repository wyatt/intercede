# FocusPet

A macOS menu bar app that nudges you off distracting websites using a retro pixel-art companion sprite.

When you spend too long on a tracked site (YouTube, Reddit, etc.), St. Alphonsus Liguori, a small animated pixel-art bishop, walks onto your screen, raises a hand, declares "This is not Liguorian!" along with a nudge message, waves the distraction away (with the browser extension, the page itself dissolves), and walks off when you tap him. Unlike traditional blockers, FocusPet doesn't restrict — it nudges.

---

## How It Works

- Polls your frontmost browser every ~2 seconds via AppleScript (Automation permission)
- Accumulates real wall-clock time per site per day (subdomains count toward their site; paused while the Mac sleeps or the screen is locked)
- When a site's daily budget is exceeded, a sprite overlay animates in from the screen edge
- Speech bubbles show the pet's catchphrase plus one of its own hand-written phrases — no network or API key needed
- Menu bar icon shows live tracking status and today's usage stats

---

## Current Features (v0.1)

- **Activity tracking** — real elapsed-time accumulation, AppleScript URL extraction (Chrome, Safari, Arc, Brave, Edge), AX API fallback
- **Daily budgets** — per-site time budgets, breach detection with 5-minute cooldown between nudges
- **Sprite overlay** — small non-activating window in the bottom-left of the screen under the cursor; walk in → raise hand → speak → sweep the page away (automatically, ~1.5s in) → lower hand → walk out when tapped; tap sprite or bubble to dismiss, auto-dismisses 45s after the sweep
- **Bundled pet: St. Alphonsus Liguori** — 7-animation sprite sheet shipped in the app, so nudges never depend on the network; his catchphrase "This is not Liguorian!" heads every bubble
- **Menu bar** — pixel-art icon, popover with live budget bars per site, debug status indicator
- **Settings** — site list CRUD (accepts bare hosts or pasted URLs), per-site daily budget (stepper, minutes, saved immediately), pet picker with preview
- **Curated companions** — five more pets from [petdex.dev](https://petdex.dev), each with its own name, catchphrase, and phrases: Hazel the Fawn, Maple the Red Panda, Pip the Penguin, Bramble the Hedgehog, Boba the Axolotl. Sprites download once and are cached; St. Alphonsus stands in until they're ready
- **Persistence** — daily usage stored as JSON in Application Support, survives restarts

---

## Planned Features

### Aggressiveness Levels
Currently only **easy mode** (single tap dismisses). Planned:

| Level | Behavior |
|-------|----------|
| Easy | Tap anywhere to dismiss |
| Medium | Confirmation dialog required to dismiss |
| Hard | Pet "argues" with you; you must convince it to leave |
| Insane | Closes the tab directly (requires browser extension) |

### Pet Progression
- XP system earned from focus streaks (staying off tracked sites)
- Pet levels up over time, gains new animations and dialogue
- Streak counter shown in menu bar popover

### Richer Sprite System
- Petdex picker search and richer preview (a basic picker exists today)
- Idle animations when pet is not nudging (lives in corner of screen)

### Browser Extension (for Insane Mode)
See [docs/browser-extension.md](docs/browser-extension.md) for the blueprint (page hold + pixel dissolve synced to the pet's gesture). The effect itself is built: open `Extension/dev/harness.html` in Chrome to try it (keys: N simulate nudge, H hold, D dissolve, R reset).

**Installing the extension (Chrome):** run the app once (`make app` or `make run`) so it registers its native-messaging host, then open `chrome://extensions`, turn on **Developer mode**, click **Load unpacked**, and choose the `Extension/` folder. The ID should be `bminoilbndphincaaooginfkcjamaadc`. When a nudge fires on a tracked site, the page holds as the pet raises his hand and dissolves on his sweep; **Test Nudge** targets whatever web page is active in Chrome.
- Chrome/Safari extension that receives close-tab commands from the native app
- Communicates via native messaging or local loopback
- Required for reliable URL detection on browsers that don't expose URLs via AppleScript

### Weekly / Historical Stats
- 7-day rolling usage chart per site
- Streak history
- Export to CSV

### iCloud Sync
- Site list and budgets sync across machines via NSUbiquitousKeyValueStore

### Notifications
- Optional native notification as a softer pre-nudge at 80% of budget
- Daily summary notification at end of day

### Multi-Browser Tabs
- Aggregate time across all open browsers (currently tracks only frontmost)

### Focus Sessions
- Manual "focus mode" timer that temporarily lowers budgets or blocks entirely
- Pomodoro-style session support

---

## Architecture

```
FocusPet/
├── App/                    # @main entry, AppDelegate, wiring
├── Monitor/                # ActivityMonitor (2s poll), BrowserURLParser (AppleScript + AX)
├── Usage/                  # UsageTracker (budgets, breach events), UsageStore (JSON persistence)
├── Nudge/                  # NudgeCoordinator, SpriteOverlayWindow, NudgeOverlayView, SpriteView
├── MenuBar/                # MenuBarController (NSStatusItem), StatsView
├── Settings/               # SettingsView (sites, budgets, pet)
├── Pets/                   # Pet (roster, names, phrases), SpriteSheet, PetLibrary, PetdexClient
├── Resources/Pets/         # bishop.png — packed sprite sheet bundled with the app
└── Support/                # AccessibilityPermission, Log
Art/                        # source art (bishop-source.png)
tools/pack-sprite.swift     # repacks source art into the uniform grid the app slices
```

### Sprite sheets

Sprites are described by `SpriteSheet`: a uniform grid plus a clip (row, frame count, fps, loop/one-shot) for each nudge beat — `walkIn`, `idle`, `alert`, `talk`, `dismiss`, `settle`, `walkOut`. The bishop is a 6×7 grid of 176×200 cells:

| Row | Clip | Frames | |
|-----|------|--------|---|
| 1 | walkIn | 6 | loop, facing right |
| 2 | idle | 4 | loop |
| 3 | alert | 6 | once — raises hand ("Stop!") |
| 4 | talk | 6 | loop while the bubble is shown |
| 5 | dismiss | 6 | once — sweeping gesture with golden sparkles |
| 6 | settle | 4 | once — lowers hand |
| 7 | walkOut | 6 | loop, facing left |

The original art isn't on an even grid and its baselines drift between rows, so `make sprites` repacks `Art/bishop-source.png`: it finds each frame by alpha, drops the matte fringe, and bottom-aligns every frame to a shared baseline. Petdex sheets (8×9) map their rows onto the same clips.

Key design decisions:
- All classes are `@MainActor` — no concurrency complexity, all UI and state on main thread
- AppleScript for URL extraction (Automation TCC permission persists across binary rebuilds; Accessibility TCC does not for unsigned builds)
- JSON flat files for usage data (one file per day, trivial to inspect/debug)
- Pets and their phrases are a fixed roster in `Pet.swift`; to add one, give it a Petdex sprite URL (standard 8×9 sheet), a catchphrase, and phrases (`%@` becomes the site)

---

## Development

**Requirements:** macOS 14+, Xcode 16+, [xcodegen](https://github.com/yonaskolb/XcodeGen)

```bash
# Install xcodegen (one-time)
brew install xcodegen

# Build and install to ~/Applications (keeps TCC permission stable)
make run

# Run unit tests
make test

# Reset Accessibility permission after changing bundle ID
make reset-tcc
```

On first launch after `make run`:
1. macOS prompts for **Automation** permission (for each browser you use) — click Allow
2. Pick a companion in Settings → Pet (optional)
3. Adjust per-site budgets in the Sites tab

`make build`/`make test` regenerate the Xcode project from `project.yml` first, so new files are picked up automatically. Required entitlements live in `project.yml` — xcodegen rewrites `FocusPet.entitlements` from it.

**Note:** Always use `make run` rather than launching from DerivedData directly. Unsigned builds use ad-hoc code signing (binary-hash-based), so the Accessibility TCC entry resets on each rebuild. Installing to a fixed path (`~/Applications/FocusPet.app`) and using Automation (bundle-ID-based) sidesteps this entirely.
