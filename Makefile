.PHONY: build install diagnose test run icon clean

build:
	@Scripts/build-app.sh

# Replaces any running copy, so `make install` is also the upgrade path.
install: build
	@echo "==> Installing to /Applications"
	@pkill -x SecondBright 2>/dev/null || true
	@rm -rf /Applications/SecondBright.app
	@cp -R build/SecondBright.app /Applications/
	@echo "==> Launching"
	@open /Applications/SecondBright.app
	@echo "SecondBright is now in your menu bar."

# Prints what the DDC layer can see. Start here when the slider misbehaves.
diagnose: build
	@build/SecondBright.app/Contents/MacOS/SecondBright --diagnose

run: build
	@open build/SecondBright.app

test:
	@swift run SecondBrightChecks

# Redraws the app icon from Scripts/make-icon.swift and repackages the .icns.
icon:
	@mkdir -p build/AppIcon.iconset
	@swiftc -O -o build/make-icon Scripts/make-icon.swift
	@build/make-icon build/AppIcon.iconset
	@iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "==> Wrote Resources/AppIcon.icns"

clean:
	@rm -rf build .build
