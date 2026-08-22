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
| `make icon` | Repackages `Resources/AppIcon.png` into `Resources/AppIcon.icns` |
| `make clean` | Removes `build/` and `.build/` |

## Cutting a release

1. Bump `CFBundleShortVersionString` in `Resources/Info.plist`.
2. Add a `## <version>` section to `CHANGELOG.md`. This is what people read on
   the download page, so write it for them — what's different when they use it,
   not which files moved.
3. Tag and push:

   ```bash
   git tag v1.2 && git push origin v1.2
   ```

`.github/workflows/release.yml` builds the disk image on an Apple Silicon runner
and publishes it. Two checks guard it: the tag has to match the plist version,
so a `v1.2` release can't ship a 1.1 binary, and the changelog has to have a
section for that version, so a release can't go out with an empty body.

Release notes come from `Scripts/release-notes.sh <version>`, which prints the
changelog section plus the standing install steps. Run it to preview what a
release will say. **Don't publish by hand with `gh release create`** — the tag
push already triggers the workflow, and a release created first makes that run
fail on "a release with the same tag name already exists".

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
   lamp, so it helps less with eye strain in a dark room. The popover says when
   this mode is active, so you're never left guessing.

The slider spans the panel's full range, 100% down to black. Reaching black
takes both mechanisms, because neither gets there alone: the backlight has a
floor of its own well above zero, and gamma can only darken what's rendered. So
in DDC mode gamma stays out of the way above `GammaDimmer.crossoverPercent`
(20%) and ramps to zero below it, while the backlight drops across the whole
range. In software mode gamma does all of it.

Both are linear in gamma-encoded space rather than in emitted light, which is
already close to perceptually even: `CGSetDisplayTransferByFormula` scales the
encoded value, and light output goes as roughly its 2.2 power.

"Black" is as black as the panel allows. On an LCD the backlight is still lit at
0%, so a faint glow remains; on OLED it is genuinely black. Putting the panel
into DDC standby (VCP `0xD6`) would kill the glow too, at the cost of a
multi-second wake and a "no signal" banner on some monitors — deliberately not
done.

The probe is a real DDC read of the luminance feature, not a capability
advertisement: a display can claim DDC and still refuse it, and an unresponsive
panel returns an all-zero buffer that would otherwise parse as a valid zero and
make the app believe it was working while doing nothing.

### The path a slider drag takes

1. `BrightnessPopover` writes `controller.percent`.
2. `BrightnessController` persists the value and schedules an apply 50 ms out,
   cancelling any pending one — DDC cannot survive raw slider traffic, and the
   coalescing guarantees the final value still lands.
3. In DDC mode the gamma ramp is set directly and the luminance write goes to a
   serial queue (the protocol needs paced, ordered, blocking I/O, and it must
   not run on the main thread or the slider stutters); transactions are spaced
   50 ms apart. In software mode only the gamma curve is set.
   The luminance value is scaled against the maximum the panel reported, which
   is routinely not 100 — writing the percentage straight through would cap a
   0...255 display at about 39% of its range.
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
| `Sources/SecondBrightCore/GammaDimmer.swift` | Gamma dimming: all of software mode, the bottom of DDC mode |
| `Sources/SecondBrightCore/BrightnessController.swift` | Level, mode selection, throttling, persistence |
| `Sources/SecondBrightCore/DisplayIdentity.swift` | Picking and identifying the external display |
| `Sources/SecondBrightCore/DisplayWatcher.swift` | Connect / disconnect / wake handling |
| `Sources/SecondBrightCore/Diagnostics.swift` | `--diagnose` output |
| `Sources/SecondBright/` | SwiftUI `MenuBarExtra` and popover |
| `Sources/SecondBrightChecks/` | `make test` |
| `Scripts/build-app.sh` | Assembles the `.app` bundle |
| `Scripts/make-icon.sh` | Repackages the app icon (`make icon`) |
| `Scripts/make-dmg.sh` | Builds the installer disk image (`make dmg`) |
| `Scripts/make-dmg-background.swift` | Draws the disk image's background |

SwiftPM only produces a bare executable, and with Command Line Tools there is no
`xcodebuild` to make a bundle — so `build-app.sh` assembles `Contents/` by hand
and ad-hoc signs it. `MenuBarExtra` needs a real bundle (and the Info.plist's
`LSUIElement`) to behave.

## The icon

Designed in Apple's Icon Composer. `Resources/AppIcon.png` is the source of
truth — 1024x1024, artwork already on the macOS icon grid — and `make icon`
resizes it into the ten entries `iconutil` needs to produce
`Resources/AppIcon.icns`. Edit the PNG, never the `.icns`.

If you re-export from Icon Composer, choose the **macOS** platform. An iOS
export is full-bleed: its rounded plate runs to all four edges of the canvas,
where a macOS icon sits inset with transparent margin around it. Dropping an
iOS export in unchanged makes SecondBright render noticeably larger than every
other app in Finder.

Icon Composer also emits dark, clear, and tinted variants. A `.icns` holds one
appearance only, so those go unused here; picking them up would mean compiling
the `.icon` with `actool` into an asset catalog and switching Info.plist to
`CFBundleIconName`. That needs full Xcode, which this build deliberately does
not require.

The disk image background is drawn in code, by
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
- **Zero means black, and the way back is the cursor.** Dimming used to stop at
  25%, on the grounds that a black screen hides the slider you need to undo it.
  The floor solved that by taking the feature away. Instead, while the level is
  exactly 0 the controller watches the cursor, and moving it onto that display
  restores 25% as a real, persisted change. The escape hatch is the thing you'd
  reach for anyway.
- **The cursor is polled, not monitored.** `NSEvent.mouseLocation` needs no
  Accessibility permission and no entitlement, where a global event monitor
  would; the poll only runs while the screen is black, so it costs nothing in
  normal use.
- **Gamma is system-wide state**, and both modes now use it. The app restores it
  on quit and on unplug, and clears it unconditionally once at launch — a run
  force-killed while black leaves nothing else to undo it. macOS also resets
  gamma on logout.
- Tests are an executable (`make test`), not a `.testTarget`: SwiftPM's macOS
  test bundles need full Xcode for test discovery, and with Command Line Tools
  only, `swift test` silently discovers nothing.
