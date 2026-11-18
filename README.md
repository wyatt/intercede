# Intercede

A Chrome extension that keeps you off distracting sites with a patron saint. Give each site a daily allowance; when it runs out, a pixel-art saint walks onto the page, raises a hand (the page pauses and dims), says a word, and sweeps the page away into pixels, leaving a veil with a **Return anyway** button that unlocks after a short countdown. Stay over your limit and they come back every few minutes.

The patrons: St. Alphonsus Liguori, St. Isidore of Seville, St. Clare of Assisi, St. Benedict, and St. Thomas Aquinas.

(An earlier macOS menu bar version lives in git at the `mac-app-final` tag.)

## Install

Get it from the [Chrome Web Store](https://chromewebstore.google.com/detail/intercede/mnihpmkigiabjkalbncnanlodlpbpool). Settings open on first install.

To run from source, open `chrome://extensions`, turn on **Developer mode**, click **Load unpacked**, and choose the `Extension/` folder (or click its reload icon after changes).

- **Popup:** today's time per site, and your patron; click the patron to send them onto the current tab.
- **Settings:** your patron, tracked sites with daily limits, and how often the patron comes back.
- **Tracking:** the active tab of a focused Chrome window counts; switching away or locking the screen stops the clock. Usage and visit counts are kept per day in `chrome.storage.local`.

## Development

```bash
make ext-test     # unit tests (Node 18+)
make sprites      # repack Art/<name>-source.png into Extension/patrons/
make icon         # rebuild the extension icons from Art/icon-source.png
make site-serve   # build and preview the landing page (site/) at http://localhost:8000
```

`Extension/dev/harness.html` is a page for tuning the dissolve effect.

### Sprite sheets

Every saint's sheet is a 6×7 grid of 176×208 cells, one row per beat:

| Row | Clip | Frames | |
|-----|------|--------|---|
| 1 | walkIn | 6 | loop, facing right |
| 2 | idle | 4 | loop |
| 3 | alert | 6 | once — raises hand |
| 4 | talk | 6 | loop while the bubble is shown |
| 5 | dismiss | 6 | once — sweeping gesture with golden sparkles |
| 6 | settle | 4 | once — lowers hand |
| 7 | walkOut | 6 | loop, facing left |

The original art isn't on an even grid, so `make sprites` repacks each `Art/<name>-source.png`: it finds each frame, removes the background and stray fragments, and bottom-aligns every frame to a shared baseline. Patrons and their phrases are listed in `Extension/src/patrons.js`.
