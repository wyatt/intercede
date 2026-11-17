.PHONY: ext-test sprites icon site site-serve store

# Chrome extension unit tests (Node 18+)
ext-test:
	node --test Extension/test/*.test.mjs

# Repack every Art/<name>-source.png into Extension/patrons/<name>.png (the uniform grid the
# extension slices). Each sheet uses the 7-row layout: 6,4,6,6,6,4,6 frames.
sprites:
	@mkdir -p Extension/patrons
	@for src in Art/*-source.png; do \
		name=$$(basename "$$src" -source.png); \
		swift tools/pack-sprite.swift "$$src" "Extension/patrons/$$name.png" 6,4,6,6,6,4,6 | tail -1; \
		grep -q "\"sheet\": \"$$name\"" Extension/src/patrons.js || \
			echo "warning: no patron uses '$$name' (sheet in Extension/src/patrons.js) — misspelled file name?"; \
	done

# Rebuild the extension icons from Art/icon-source.png
icon:
	swift tools/make-icon.swift Extension/icons

# Build the landing page: the demo's copy of the extension (site/ext) and the download zip
# (site/intercede.zip). Vercel runs the same script (vercel.json).
site:
	node tools/build.mjs site

# The Chrome Web Store upload: dist/intercede-<version>.zip (no manifest key, no dev/ or test/)
store:
	node tools/build.mjs store

site-serve: site
	cd site && python3 -m http.server 8000
