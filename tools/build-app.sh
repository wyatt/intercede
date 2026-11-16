#!/bin/bash
# Builds, signs (ad hoc), installs, and launches Intercede.app using only the Command Line Tools —
# no Xcode needed. Same layout as the Xcode build: app binary + IntercedeBridge helper.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=.build/manual/Intercede.app
DEST="$HOME/Applications/Intercede.app"
SWIFTC=(swiftc -O -swift-version 6 -target "$(uname -m)-apple-macos14.0")

rm -rf .build/manual
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" "$OUT/Contents/Helpers"

"${SWIFTC[@]}" -parse-as-library -o "$OUT/Contents/MacOS/Intercede" $(find Intercede -name '*.swift')
"${SWIFTC[@]}" -o "$OUT/Contents/Helpers/IntercedeBridge" IntercedeBridge/main.swift

cp Intercede/Resources/Info.plist "$OUT/Contents/Info.plist"
plutil -insert CFBundleExecutable -string Intercede "$OUT/Contents/Info.plist"
cp Intercede/Resources/Patrons/*.png Intercede/Resources/AppIcon.icns "$OUT/Contents/Resources/"

# Inside-out: sign the helper before the bundle that contains it.
codesign --force --sign - --options runtime "$OUT/Contents/Helpers/IntercedeBridge"
codesign --force --sign - --options runtime --entitlements Intercede/Resources/Intercede.entitlements "$OUT"

pkill -x Intercede 2>/dev/null && sleep 1 || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$OUT" "$DEST"
touch "$DEST"
open "$DEST"
echo "Installed and launched $DEST"
