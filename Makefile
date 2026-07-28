DERIVED = $(HOME)/Library/Developer/Xcode/DerivedData
APP_NAME = FocusPet
SCHEME = FocusPet
BUNDLE_ID = com.focuspet.app
BUILD_DIR = $(shell xcodebuild -project $(APP_NAME).xcodeproj -scheme $(SCHEME) -configuration Debug -showBuildSettings 2>/dev/null | grep '^\s*BUILT_PRODUCTS_DIR' | head -1 | sed 's/.*= //')
INSTALL_DIR = $(HOME)/Applications

.PHONY: build install run clean reset-tcc

build:
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(SCHEME) -configuration Debug build

install: build
	pkill -x $(APP_NAME) 2>/dev/null || true
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	cp -R "$(BUILD_DIR)/$(APP_NAME).app" $(INSTALL_DIR)/$(APP_NAME).app
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

run: install
	open $(INSTALL_DIR)/$(APP_NAME).app

reset-tcc:
	tccutil reset Accessibility $(BUNDLE_ID)
	@echo "Accessibility permission reset — re-grant on next launch"

clean:
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(SCHEME) clean
