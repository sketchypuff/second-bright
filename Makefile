.PHONY: build install diagnose test run clean

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

clean:
	@rm -rf build .build
