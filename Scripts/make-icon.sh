#!/bin/bash
# Repackages Resources/AppIcon.png into Resources/AppIcon.icns.
#
# The source PNG is the icon exactly as macOS should draw it: 1024x1024, with
# the artwork already sitting on the macOS icon grid (an 824pt body centred in
# the canvas, transparent margin around it). Nothing here insets or reshapes --
# it only resizes. So if you re-export from Icon Composer, pick the *macOS*
# platform and drop the 1024 result straight in; an iOS export is full-bleed
# and will render oversized next to other apps.
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="Resources/AppIcon.png"
SET="build/AppIcon.iconset"

[ -f "$SRC" ] || { echo "error: $SRC is missing" >&2; exit 1; }

echo "==> Rendering sizes from $SRC"
rm -rf "$SET"
mkdir -p "$SET"

# The ten entries iconutil expects. @2x is the same pixel count as the next
# size up, but both names have to be present.
for spec in "16 icon_16x16" "32 icon_16x16@2x" \
            "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" \
            "256 icon_256x256" "512 icon_256x256@2x" \
            "512 icon_512x512" "1024 icon_512x512@2x"; do
    px="${spec% *}"
    name="${spec#* }"
    sips -s format png -z "$px" "$px" "$SRC" --out "$SET/$name.png" >/dev/null
done

iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "==> Wrote Resources/AppIcon.icns"
