#!/bin/bash
# Builds SecondBright.dmg -- the thing a non-developer downloads.
#
# The disk image opens to a window with the app on the left, an Applications
# folder on the right, and an arrow between them, so the install is a single
# drag with no instructions to follow.
#
# That window layout is stored in a .DS_Store, which only Finder can write. This
# script drives Finder over AppleScript to produce it, then caches the result in
# Resources/dmg/DS_Store so the build can be repeated on a machine where Finder
# automation is unavailable -- notably a CI runner, which has no logged-in
# session to script. Commit that cached file; CI depends on it.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/SecondBright.app"
VOLUME="SecondBright"
STAGING="build/dmg-staging"
SCRATCH="build/scratch.dmg"
DS_STORE_CACHE="Resources/dmg/DS_Store"
MOUNTPOINT="/Volumes/$VOLUME"

# Set FORCE_LAYOUT=1 to re-run Finder and refresh the cached .DS_Store, which is
# what you want after moving anything in make-dmg-background.swift.
FORCE_LAYOUT="${FORCE_LAYOUT:-0}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/SecondBright-$VERSION.dmg"

[ -d "$APP" ] || Scripts/build-app.sh

# --- Background image -------------------------------------------------------
# Two scales packed into one multi-resolution TIFF, which is how a DMG
# background stays sharp on a Retina display.
echo "==> Drawing background"
swiftc -O -o build/make-dmg-background Scripts/make-dmg-background.swift
build/make-dmg-background build >/dev/null
tiffutil -cathidpicheck build/dmg-background.png build/dmg-background@2x.png \
    -out build/dmg-background.tiff >/dev/null

# --- Staging ----------------------------------------------------------------
echo "==> Staging"
# A stale mount from an interrupted run would make hdiutil pick a different
# volume name, and the AppleScript below would then address the wrong window.
hdiutil detach "$MOUNTPOINT" -force >/dev/null 2>&1 || true

rm -rf "$STAGING" "$SCRATCH"
mkdir -p "$STAGING/.background"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp build/dmg-background.tiff "$STAGING/.background/background.tiff"

NEEDS_LAYOUT=1
if [ -f "$DS_STORE_CACHE" ] && [ "$FORCE_LAYOUT" != "1" ]; then
    echo "==> Using cached window layout ($DS_STORE_CACHE)"
    cp "$DS_STORE_CACHE" "$STAGING/.DS_Store"
    NEEDS_LAYOUT=0
fi

# --- Read/write image -------------------------------------------------------
# Finder can only be told to arrange a window it can actually write to, so the
# layout pass needs a UDRW image; it is compressed to UDZO at the end.
echo "==> Creating scratch image"
hdiutil create -quiet -srcfolder "$STAGING" -volname "$VOLUME" \
    -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW -ov "$SCRATCH"

if [ "$NEEDS_LAYOUT" = "1" ]; then
    echo "==> Laying out the window with Finder"
    hdiutil attach -quiet -noautoopen -mountpoint "$MOUNTPOINT" "$SCRATCH"

    # Icon centres here must match appIconCenter / appsIconCenter in
    # Scripts/make-dmg-background.swift, or the arrow will not line up.
    if osascript <<-'APPLESCRIPT'
		tell application "Finder"
		    tell disk "SecondBright"
		        open
		        set current view of container window to icon view
		        set toolbar visible of container window to false
		        set statusbar visible of container window to false
		        set sidebar width of container window to 0
		        -- 660x420 content, matching the background image.
		        set the bounds of container window to {200, 120, 860, 540}
		        set opts to the icon view options of container window
		        set arrangement of opts to not arranged
		        set icon size of opts to 96
		        set text size of opts to 12
		        set label position of opts to bottom
		        set background picture of opts to file ".background:background.tiff"
		        set position of item "SecondBright.app" of container window to {170, 198}
		        set position of item "Applications" of container window to {490, 198}
		        close
		        open
		        update without registering applications
		        delay 2
		        close
		    end tell
		end tell
		APPLESCRIPT
    then
        # Finder writes .DS_Store lazily; give it a moment to land before the
        # volume goes away, then keep it so CI never needs Finder at all.
        sync; sleep 2
        if [ -f "$MOUNTPOINT/.DS_Store" ]; then
            mkdir -p "$(dirname "$DS_STORE_CACHE")"
            cp "$MOUNTPOINT/.DS_Store" "$DS_STORE_CACHE"
            echo "==> Cached window layout to $DS_STORE_CACHE (commit this)"
        fi
    else
        echo "!!  Finder automation failed -- the disk image will still install," >&2
        echo "!!  but without the drag-to-Applications layout. Run this on a Mac" >&2
        echo "!!  with Finder access and commit $DS_STORE_CACHE." >&2
    fi

    hdiutil detach "$MOUNTPOINT" -quiet -force
fi

# --- Compress ---------------------------------------------------------------
echo "==> Compressing"
rm -f "$DMG"
hdiutil convert -quiet "$SCRATCH" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -rf "$SCRATCH" "$STAGING"

echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
