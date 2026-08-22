# SecondBright

A macOS menu bar slider for your external monitor's brightness.

Click the sun icon in the top bar, drag the slider, done — no reaching for the
buttons on the monitor itself. It controls **only** the external display; the
built-in Retina screen is never touched.

## Install

```
make install
```

Builds, ad-hoc signs, drops `SecondBright.app` into `/Applications`, and launches it.
Re-run it to upgrade. Requires Swift 6 (Command Line Tools are enough — no Xcode needed).

## How it controls the display

Two mechanisms, chosen automatically by probing the monitor at launch and on every
reconnect:

1. **DDC/CI** — real backlight control, the same thing the monitor's own buttons do.
   This is preferred whenever the panel accepts it.
2. **Software dimming** — a gamma adjustment applied to that display only. Used when
   the backlight is unreachable. It darkens the *image* rather than the lamp, so it
   can't go above 100% and it helps less with eye strain in a dark room. The popover
   says when this mode is active, so you're never left guessing.

### On this Mac's LG UltraFine, mode 2 is what runs

Worth recording, because it looks like a bug and isn't. The monitor answers I2C
perfectly — its EDID reads back cleanly at address `0x50`, identifying as
manufacturer `GSM`. But every DDC/CI request to address `0x37` is refused with
`0xE0114000`, whether reading or writing. macOS agrees independently:
`DisplayServicesCanChangeBrightness` returns `false` for this display and `true`
for the built-in one.

So the fault is localised to DDC/CI on the panel, not to the cable, the Mac, or
this app. HDR was ruled out — the display reports an EDR headroom of 1.0, meaning
HDR is off.

**If your monitor has a `DDC/CI` setting in its on-screen menu, turning it on may
enable real backlight control.** SecondBright re-probes on every replug and relaunch,
so it will pick that up on its own and switch to mode 1 with no changes here.

Run `make diagnose` to see which mode applies and why:

```
IOAVService symbols resolved : true
External displays            : 1
  - LG ULTRAFINE  id=2  key=7789-23489-338818
    macOS can set backlight   : false
EDID read (0x50)             : ok, manufacturer GSM
DDC luminance (0x37)         : FAILED
```

## Layout

| Path | Role |
|---|---|
| `Sources/SecondBrightCore/DDCService.swift` | DDC/CI over I2C on Apple Silicon |
| `Sources/SecondBrightCore/GammaDimmer.swift` | Software dimming fallback |
| `Sources/SecondBrightCore/BrightnessController.swift` | Level, mode selection, throttling, persistence |
| `Sources/SecondBrightCore/DisplayWatcher.swift` | Connect / disconnect / wake handling |
| `Sources/SecondBrightCore/Diagnostics.swift` | `--diagnose` output |
| `Sources/SecondBright/` | SwiftUI `MenuBarExtra` and popover |
| `Sources/SecondBrightChecks/` | `make test` |
| `Scripts/build-app.sh` | Assembles the `.app` bundle |

## Notes and limitations

- **One external display**, by design. Display identity is already tracked per
  monitor, so extending this isn't a rewrite.
- **No scroll-over-icon.** That needs an AppKit `NSStatusItem`; this app is
  SwiftUI-only on purpose.
- **DDC uses private Apple symbols** (`IOAVServiceCreateWithService` and friends).
  There is no public API for this on Apple Silicon. They're resolved with `dlsym`
  at runtime, so if a future macOS removes them the app degrades to software
  dimming instead of failing to launch.
- **Software dimming never goes fully black** — it stops at 25%, because a screen
  dimmed to zero would hide the very slider you need to undo it.
- **Gamma is system-wide state.** The app restores it on quit and on unplug. If it
  is ever force-killed while dimming, run `make diagnose` or just relaunch;
  macOS also resets gamma on logout.
- Tests are an executable (`make test`), not a `.testTarget`: SwiftPM's macOS test
  bundles need full Xcode for test discovery, and with Command Line Tools only,
  `swift test` silently discovers nothing.
