APP_NAME = FocusPet
SCHEME = FocusPet
BUNDLE_ID = com.focuspet.app
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

# Repack every Art/<name>-source.png into FocusPet/Resources/Pets/<name>.png (the uniform grid the app
# slices). Each sheet uses the 7-row layout: 6,4,6,6,6,4,6 frames.
sprites:
	@for src in Art/*-source.png; do \
		name=$$(basename "$$src" -source.png); \
		swift tools/pack-sprite.swift "$$src" "FocusPet/Resources/Pets/$$name.png" 6,4,6,6,6,4,6 | tail -1; \
	done

# Rebuild the app icon from the bishop sprite
icon:
	swift tools/make-icon.swift FocusPet/Resources/Pets/bishop.png FocusPet/Resources/AppIcon.icns

reset-tcc:
	tccutil reset Accessibility $(BUNDLE_ID)
	tccutil reset AppleEvents $(BUNDLE_ID)
	@echo "Accessibility + Automation permissions reset — re-grant on next launch"

clean:
	rm -rf $(DERIVED)
