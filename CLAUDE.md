# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

SecondBright is a macOS menu-bar app (SwiftUI `MenuBarExtra`) that controls the
brightness of the **external** display only. macOS 14+, Apple Silicon, Swift 6
toolchain with Command Line Tools (full Xcode is deliberately not required).

[CONTRIBUTING.md](CONTRIBUTING.md) is the long-form reference — design
reasoning, release process, DMG layout, icon pipeline, and a "Notes and
limitations" section recording decisions that look like bugs but aren't. Read it
before changing display behaviour, packaging, or the icon.

## Commands

```bash
make build      # builds and assembles build/SecondBright.app
make install    # build + install to /Applications + launch (also the upgrade path)
make run        # build + open from build/
make test       # runs Sources/SecondBrightChecks
make diagnose   # prints what the DDC layer sees — start here when the slider misbehaves
make dmg        # builds the installer disk image
make icon       # repackages Resources/AppIcon.png into AppIcon.icns
make clean
```

`make test` runs the whole check executable; there is no per-test filter. To run
a subset, edit or comment out `suite(...)` blocks in
[Sources/SecondBrightChecks/main.swift](Sources/SecondBrightChecks/main.swift).
Checks must be pure — they run without a display attached, so anything touching
real hardware belongs in `make diagnose` instead.

`swift test` finds nothing: SwiftPM's macOS test bundles need full Xcode for
test discovery, so the checks are an `executableTarget`, not a `.testTarget`.

Persisted levels live in `com.yashshenai.SecondBright`; clear them with
`defaults delete com.yashshenai.SecondBright`.

## Architecture

Three targets: `SecondBrightCore` (all display logic, no UI), `SecondBright`
(the SwiftUI menu-bar app), `SecondBrightChecks` (the test executable).

**Two dimming mechanisms, chosen by probing the panel** at launch and on every
reconnect:

- `DDCService` — real backlight control over I2C using private Apple symbols
  (`IOAVServiceCreateWithService` and friends) resolved via `dlsym`, so a future
  macOS removing them degrades to software dimming rather than failing to launch.
- `GammaDimmer` — a per-display gamma adjustment. All of software mode; in DDC
  mode it stays out of the way above `crossoverPercent` (20%) and ramps to zero
  below it, because a backlight alone can't reach black.

The probe is a real DDC *read* of luminance, not a capability advertisement — a
panel can claim DDC and refuse it, and an all-zero reply from an unresponsive
panel must not parse as a valid zero (`DDCService.parseReply` enforces this).

**A slider drag's path:** `BrightnessPopover` writes `controller.percent` →
`BrightnessController` persists and schedules an apply 50 ms out, cancelling any
pending one → gamma is set on the main actor while the DDC luminance write goes
to a serial queue (paced, ordered, blocking I/O that must not stutter the
slider) → `DisplayWatcher` re-probes 2 s after any display reconfiguration.

Two things that look wrong and are not: the DDC luminance value is scaled
against the maximum the panel reports (routinely not 100), and the target
display is chosen as "not built-in" rather than by `CGMainDisplayID` — the
external monitor is often the main display.

**Zero means black**, and the escape is the cursor: while the level is exactly
0, `BrightnessController` polls `NSEvent.mouseLocation` (polling avoids the
Accessibility permission a global monitor would need) and restores
`wakePercent` (25%) as a real, persisted change when the cursor lands on that
display. Gamma is system-wide state, so it is restored on quit and unplug and
cleared unconditionally once at launch.

`--diagnose` short-circuits before any UI exists, so it stays usable when the
GUI is what's broken.

## Packaging

`Scripts/build-app.sh` assembles `Contents/` by hand and **ad-hoc signs** it —
there is no `xcodebuild` here, and `MenuBarExtra` needs a real bundle with
`LSUIElement`. Keep the ad-hoc signature: an unsigned app on Apple Silicon fails
with "damaged and can't be opened" instead of the milder warning users can get
past.

Releases are tag-driven. Bump `CFBundleShortVersionString` in
`Resources/Info.plist`, add a `## <version>` section to `CHANGELOG.md` (written
for users — it becomes the download page text), then push the tag. CI enforces
that both match. **Never `gh release create`** — the tag push already triggers
the workflow and a pre-made release makes it fail.

`Resources/AppIcon.png` (1024×1024, macOS export from Icon Composer) is the
source of truth; never edit the `.icns`. `Resources/dmg/DS_Store` is committed
on purpose — only Finder can write it, and CI has no session to script.
