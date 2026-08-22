# SecondBright

A macOS menu bar slider for your external monitor's brightness.

Click the sun icon in the top bar, drag the slider, done — no reaching for the
buttons on the monitor itself. It controls **only** the external display; the
built-in Retina screen is never touched.

## What you get

- A menu bar popover with a 0–100% slider, the monitor's name, and 0 / 25 / 50 /
  100% preset buttons.
- Brightness remembered per monitor and reapplied at login, keyed on the
  display's vendor/model/serial so a different screen never inherits the wrong
  level.
- Automatic re-detection when you unplug, replug, or wake the Mac — monitors
  routinely forget their brightness across sleep, so the app reapplies rather
  than trusting its last write to have stuck.
- A "Launch at login" checkbox (`SMAppService`) and a Quit button.
- No Dock icon and no app-switcher entry (`LSUIElement`).

## Requirements

- macOS 14 or later, Apple Silicon. The DDC path uses Apple Silicon–only
  private symbols; on Intel it falls back to software dimming.
- Swift 6 toolchain. Xcode Command Line Tools are enough — full Xcode is not
  needed.

## Install

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

To uninstall, quit from the popover and remove the bundle:

```bash
pkill -x SecondBright; rm -rf /Applications/SecondBright.app
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
| `make diagnose` | Prints what the DDC layer can see (start here when the slider misbehaves) |
| `make test` | Runs the checks in `Sources/SecondBrightChecks` |
| `make icon` | Redraws the icon and repackages `Resources/AppIcon.icns` |
| `make clean` | Removes `build/` and `.build/` |

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

**If your monitor has a `DDC/CI` setting in its on-screen menu, turning it on may
enable real backlight control.** SecondBright re-probes on every replug and
relaunch, so it will pick that up on its own and switch to mode 1 with no
changes here.

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
