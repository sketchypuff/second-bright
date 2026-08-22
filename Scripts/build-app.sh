#!/bin/bash
# Assembles SecondBright.app by hand.
#
# SwiftPM only produces a bare executable, and this machine has Command Line
# Tools rather than full Xcode, so there is no xcodebuild to make a bundle.
# MenuBarExtra needs a real bundle (and Info.plist's LSUIElement) to behave.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP="build/SecondBright.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/SecondBright"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SecondBright"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
# Ad-hoc is enough for local use and for SMAppService.mainApp registration.
codesign --force --sign - --identifier com.yashshenai.SecondBright "$APP"
codesign --verify --verbose "$APP" 2>&1 | sed 's/^/    /'

echo "==> Done: $APP"
