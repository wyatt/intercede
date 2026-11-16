#!/bin/bash
# Builds, signs (ad hoc), installs, and launches FocusPet.app using only the Command Line Tools —
# no Xcode needed. Same layout as the Xcode build: app binary + FocusPetBridge helper.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=.build/manual/FocusPet.app
DEST="$HOME/Applications/FocusPet.app"
SWIFTC=(swiftc -O -swift-version 6 -target "$(uname -m)-apple-macos14.0")

rm -rf .build/manual
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" "$OUT/Contents/Helpers"

"${SWIFTC[@]}" -parse-as-library -o "$OUT/Contents/MacOS/FocusPet" $(find FocusPet -name '*.swift')
"${SWIFTC[@]}" -o "$OUT/Contents/Helpers/FocusPetBridge" FocusPetBridge/main.swift

cp FocusPet/Resources/Info.plist "$OUT/Contents/Info.plist"
plutil -insert CFBundleExecutable -string FocusPet "$OUT/Contents/Info.plist"
cp FocusPet/Resources/Pets/*.png FocusPet/Resources/AppIcon.icns "$OUT/Contents/Resources/"

# Inside-out: sign the helper before the bundle that contains it.
codesign --force --sign - --options runtime "$OUT/Contents/Helpers/FocusPetBridge"
codesign --force --sign - --options runtime --entitlements FocusPet/Resources/FocusPet.entitlements "$OUT"

pkill -x FocusPet 2>/dev/null && sleep 1 || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$OUT" "$DEST"
touch "$DEST"
open "$DEST"
echo "Installed and launched $DEST"
