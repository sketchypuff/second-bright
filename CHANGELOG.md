# Changelog

Notes for each released version. `Scripts/release-notes.sh` reads the section
matching a tag and hands it to the release workflow, so what's written here is
what people see on the download page — write it for them, not for the repo.

## 1.2

- A new app icon, designed in Icon Composer.

Nothing else changed: the brightness behaviour is identical to 1.1, so there's
no reason to update beyond liking the new icon better.

## 1.1

The first public release.

- A brightness slider for the external monitor, in the menu bar, with 0 / 25 /
  50 / 75 / 100% presets. The full range: 100% is the monitor's brightest, 0% is
  a black screen.
- Real backlight control over DDC/CI wherever the monitor allows it, falling
  back to dimming the picture where it doesn't. The popover says which is in
  use, because the two don't feel the same in a dark room.
- Below 20%, picture dimming joins in and carries the screen the rest of the way
  to black — every backlight has a floor of its own, well above off. On an LCD
  that leaves a faint glow; on OLED it's properly black.
- Moving the cursor onto a blacked-out monitor brings it back to 25%, so the way
  out of a black screen is the thing you'd reach for anyway.
- Remembers the level per monitor and restores it at login, on replug, and on
  wake.
- Leftover dimming is cleared at startup, so a force-quit while dark can't strand
  the screen.
- Never touches the Mac's built-in display.

## 1.0

Built but never published; no download was ever offered. Its history is in the
commits up to `7e6d921`.
