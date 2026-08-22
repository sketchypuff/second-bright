# Working on SecondBright

Everything here is for building and modifying the app. To just install and use
it, see the [README](README.md).

## Requirements

- macOS 14 or later, Apple Silicon. The DDC path uses Apple Silicon–only
  private symbols; the code falls back to software dimming without them, but
  `swift build` produces a host-architecture binary, so the released disk image
  is arm64-only and won't launch on an Intel Mac at all. Shipping to Intel would
  mean building both slices and `lipo`-ing them together.
- Swift 6 toolchain. Xcode Command Line Tools are enough — full Xcode is not
  needed.

```bash
make install
```

Builds, ad-hoc signs, drops `SecondBright.app` into `/Applications`, and
launches it. Re-run it to upgrade — it kills any running copy first, so
`install` is also the upgrade path.

To try it without installing:

```bash
make run
```

Saved brightness levels live in the app's own preferences domain
(`com.yashshenai.SecondBright`) and go away with `defaults delete
com.yashshenai.SecondBright`.

## Make targets

| Target | What it does |
|---|---|
| `make build` | Builds and assembles `build/SecondBright.app` |
| `make install` | Build, then install to `/Applications` and launch |
| `make run` | Build, then open the app from `build/` |
| `make dmg` | Builds `build/SecondBright-<version>.dmg`, the installer users download |
| `make diagnose` | Prints what the DDC layer can see (start here when the slider misbehaves) |
| `make test` | Runs the checks in `Sources/SecondBrightChecks` |
| `make icon` | Redraws the icon and repackages `Resources/AppIcon.icns` |
| `make clean` | Removes `build/` and `.build/` |

## Cutting a release

1. Bump `CFBundleShortVersionString` in `Resources/Info.plist`.
2. Tag and push:

   ```bash
   git tag v1.1 && git push origin v1.1
   ```

`.github/workflows/release.yml` builds the disk image on an Apple Silicon runner
and publishes it with install instructions attached. It refuses to build if the
tag and the plist version disagree, so a `v1.1` release can't ship a 1.0 binary.

The DMG's window layout — icon positions, the background image, the hidden
toolbar — lives in a `.DS_Store`, which only Finder can write. `make dmg` drives
Finder over AppleScript to produce one and caches it at `Resources/dmg/DS_Store`,
because a CI runner has no logged-in session to script and has to reuse it.
**That file is committed on purpose.** After moving anything in
`Scripts/make-dmg-background.swift`, refresh it locally and commit the result:

```bash
FORCE_LAYOUT=1 make dmg
```

## Distribution and signing

The app is **ad-hoc signed, not notarized**, which is why users have to approve
it once through System Settings. Notarization needs a Developer ID certificate,
and that needs the paid Apple Developer Program.

Keep the ad-hoc signature in `Scripts/build-app.sh` regardless. On Apple Silicon
an app with no signature at all fails with *"SecondBright is damaged and can't
be opened"* — a scarier message with no Open Anyway path — rather than the
milder unidentified-developer warning that users can actually get past.

The Mac App Store isn't an option either way: the DDC path uses private Apple
symbols, which is an automatic rejection.

## How it controls the display

Two mechanisms, chosen automatically by probing the monitor at launch and on
every reconnect:

1. **DDC/CI** — real backlight control, the same thing the monitor's own buttons
   do. This is preferred whenever the panel accepts it.
2. **Software dimming** — a gamma adjustment applied to that display only. Used
   when the backlight is unreachable. It darkens the *image* rather than the
   lamp, so it can't go above 100% and it helps less with eye strain in a dark
   room. The popover says when this mode is active, so you're never left
   guessing.

The probe is a real DDC read of the luminance feature, not a capability
advertisement: a display can claim DDC and still refuse it, and an unresponsive
panel returns an all-zero buffer that would otherwise parse as a valid zero and
make the app believe it was working while doing nothing.

### The path a slider drag takes

1. `BrightnessPopover` writes `controller.percent`.
2. `BrightnessController` persists the value and schedules an apply 50 ms out,
   cancelling any pending one — DDC cannot survive raw slider traffic, and the
   coalescing guarantees the final value still lands.
3. In DDC mode the write goes to a serial queue (the protocol needs paced,
   ordered, blocking I/O, and it must not run on the main thread or the slider
   stutters); transactions are spaced 50 ms apart. In software mode the gamma
   curve is set directly.
4. `DisplayWatcher` re-runs the whole probe on any display reconfiguration,
   two seconds after the change settles — monitors ignore commands sent the
   instant they reconnect.

### On this Mac's LG UltraFine, mode 2 is what runs

Worth recording, because it looks like a bug and isn't. The monitor answers I2C
perfectly — its EDID reads back cleanly at address `0x50`, identifying as
manufacturer `GSM`. But every DDC/CI request to address `0x37` is refused with
`0xE0114000`, whether reading or writing. macOS agrees independently:
`DisplayServicesCanChangeBrightness` returns `false` for this display and `true`
for the built-in one.

So the fault is localised to DDC/CI on the panel, not to the cable, the Mac, or
this app. HDR was ruled out — the display reports an EDR headroom of 1.0,
meaning HDR is off.

## Troubleshooting

Run `make diagnose` to see which mode applies and why:

```
IOAVService symbols resolved : true
External displays            : 1
  - LG ULTRAFINE  id=2  key=7789-23489-338818
    macOS can set backlight   : false
EDID read (0x50)             : ok, manufacturer GSM
DDC luminance (0x37)         : FAILED
```

How to read it:

- **EDID ok + DDC failed** — the I2C link is fine and the panel is refusing
  DDC/CI. Look for a DDC/CI toggle in the monitor's on-screen menu.
- **EDID failed** — the I2C link itself is unavailable; suspect the cable or the
  connection, not the monitor's settings.
- **No AV service opened / 0 external displays** — nothing external was
  detected. The menu bar icon shows a warning badge in this state.

`--diagnose` short-circuits before any UI is created, so it stays usable when the
GUI is the thing misbehaving.

## Layout

| Path | Role |
|---|---|
| `Sources/SecondBrightCore/DDCService.swift` | DDC/CI over I2C on Apple Silicon |
| `Sources/SecondBrightCore/GammaDimmer.swift` | Software dimming fallback |
| `Sources/SecondBrightCore/BrightnessController.swift` | Level, mode selection, throttling, persistence |
| `Sources/SecondBrightCore/DisplayIdentity.swift` | Picking and identifying the external display |
| `Sources/SecondBrightCore/DisplayWatcher.swift` | Connect / disconnect / wake handling |
| `Sources/SecondBrightCore/Diagnostics.swift` | `--diagnose` output |
| `Sources/SecondBright/` | SwiftUI `MenuBarExtra` and popover |
| `Sources/SecondBrightChecks/` | `make test` |
| `Scripts/build-app.sh` | Assembles the `.app` bundle |
| `Scripts/make-icon.swift` | Draws the app icon (`make icon`) |
| `Scripts/make-dmg.sh` | Builds the installer disk image (`make dmg`) |
| `Scripts/make-dmg-background.swift` | Draws the disk image's background |

SwiftPM only produces a bare executable, and with Command Line Tools there is no
`xcodebuild` to make a bundle — so `build-app.sh` assembles `Contents/` by hand
and ad-hoc signs it. `MenuBarExtra` needs a real bundle (and the Info.plist's
`LSUIElement`) to behave.

## The icon

Drawn in code with CoreGraphics rather than exported from a design tool, so it
re-renders sharply at every size and the geometry stays editable without binary
assets. `make icon` redraws it and repackages `Resources/AppIcon.icns`.

The plate is a superellipse rather than a rounded rectangle: macOS uses
continuous corners, and a plain rounded rect reads as subtly wrong next to real
system icons.

The disk image background is drawn the same way, by
`Scripts/make-dmg-background.swift`. Its icon-centre constants are duplicated in
the AppleScript inside `make-dmg.sh`; move one and the arrow stops lining up
with the icons.

## Notes and limitations

- **One external display**, by design. Display identity is already tracked per
  monitor, so extending this isn't a rewrite.
- **The target is "not built-in", never macOS's main-display flag.** On this Mac
  the external monitor *is* the main display, so keying off `CGMainDisplayID`
  would drive exactly the wrong screen.
- **No scroll-over-icon.** That needs an AppKit `NSStatusItem`; this app is
  SwiftUI-only on purpose.
- **DDC uses private Apple symbols** (`IOAVServiceCreateWithService` and
  friends). There is no public API for this on Apple Silicon. They're resolved
  with `dlsym` at runtime, so if a future macOS removes them the app degrades to
  software dimming instead of failing to launch.
- **Software dimming never goes fully black** — it stops at 25%, because a screen
  dimmed to zero would hide the very slider you need to undo it.
- **Gamma is system-wide state.** The app restores it on quit and on unplug. If
  it is ever force-killed while dimming, relaunching fixes it; macOS also resets
  gamma on logout.
- Tests are an executable (`make test`), not a `.testTarget`: SwiftPM's macOS
  test bundles need full Xcode for test discovery, and with Command Line Tools
  only, `swift test` silently discovers nothing.
