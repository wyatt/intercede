.PHONY: ext-test sprites icon site site-serve

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

# Build the landing page: copy the extension's scripts, sprites and icons into site/ext (for the
# live demo) and zip the extension for download. Deploy the site/ folder as static files.
site:
	rm -rf site/ext site/intercede.zip
	mkdir -p site/ext/patrons
	cp Extension/src/dissolve.js Extension/src/patron.js Extension/src/patrons.js site/ext/
	cp Extension/patrons/*.png site/ext/patrons/
	cp Extension/icons/icon-32.png Extension/icons/icon-128.png site/ext/
	cd Extension && zip -qr ../site/intercede.zip . -x 'dev/*' 'test/*' '.DS_Store'

site-serve: site
	cd site && python3 -m http.server 8000
