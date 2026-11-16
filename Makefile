APP_NAME = Intercede
SCHEME = Intercede
BUNDLE_ID = com.intercede.app
DERIVED = .build/DerivedData
BUILD_DIR = $(DERIVED)/Build/Products/Debug
INSTALL_DIR = $(HOME)/Applications
XCODEBUILD = xcodebuild -project $(APP_NAME).xcodeproj -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED)

.PHONY: generate build test install run app clean reset-tcc sprites icon

# Regenerate the Xcode project from project.yml (needed after adding/removing files)
generate:
	xcodegen generate

build: generate
	$(XCODEBUILD) build

test: generate
	$(XCODEBUILD) test

install: build
	pkill -x $(APP_NAME) 2>/dev/null || true
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	cp -R "$(BUILD_DIR)/$(APP_NAME).app" $(INSTALL_DIR)/$(APP_NAME).app
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

run: install
	open $(INSTALL_DIR)/$(APP_NAME).app

# Build + install + launch without Xcode (Command Line Tools only)
app:
	tools/build-app.sh

# Repack every Art/<name>-source.png into Intercede/Resources/Patrons/<name>.png (the uniform grid the app
# slices). Each sheet uses the 7-row layout: 6,4,6,6,6,4,6 frames.
sprites:
	@for src in Art/*-source.png; do \
		name=$$(basename "$$src" -source.png); \
		swift tools/pack-sprite.swift "$$src" "Intercede/Resources/Patrons/$$name.png" 6,4,6,6,6,4,6 | tail -1; \
		grep -q "sheetName: \"$$name\"" Intercede/Patrons/Patron.swift || \
			echo "warning: no patron uses '$$name' (sheetName in Intercede/Patrons/Patron.swift) — misspelled file name?"; \
	done

# Rebuild the app icon from the bishop sprite
icon:
	swift tools/make-icon.swift Intercede/Resources/Patrons/liguori.png Intercede/Resources/AppIcon.icns

reset-tcc:
	tccutil reset Accessibility $(BUNDLE_ID)
	tccutil reset AppleEvents $(BUNDLE_ID)
	@echo "Accessibility + Automation permissions reset — re-grant on next launch"

clean:
	rm -rf $(DERIVED)
