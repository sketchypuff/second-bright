.PHONY: build install diagnose test run icon dmg clean

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

# Builds the installer disk image users download. See Scripts/make-dmg.sh.
dmg: build
	@Scripts/make-dmg.sh

# Repackages Resources/AppIcon.png into Resources/AppIcon.icns.
icon:
	@Scripts/make-icon.sh

clean:
	@rm -rf build .build
