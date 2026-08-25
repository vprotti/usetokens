#!/bin/bash
# Packages dist/UseTokens.app into a styled DMG at www/downloads/UseTokens.dmg.
# Requires dist/UseTokens.app and dist/dmg-bg.png (run scripts/build.sh first).
#
# NOTE: the Finder-styling step (osascript) triggers a one-time macOS prompt
# "…wants to control Finder" — run interactively at least once and allow it.
# Error -1743 from osascript means the permission was denied
# (fix: System Settings > Privacy & Security > Automation, or `tccutil reset AppleEvents`).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
DIST="$ROOT/dist"
STAGE="$DIST/dmg-stage"
RW_DMG="$DIST/UseTokens-rw.dmg"
# Fail loudly: a silent 1.0.0 fallback would republish an old version number.
APP_VERSION="$(defaults read "$DIST/UseTokens.app/Contents/Info" CFBundleShortVersionString)" \
  || { echo "error: could not read the version from dist/UseTokens.app — run scripts/build.sh first" >&2; exit 1; }
OUT_DMG="$DIST/UseTokens-$APP_VERSION.dmg"
VOL="/Volumes/UseTokens"

[ -d "$DIST/UseTokens.app" ] || { echo "error: dist/UseTokens.app missing — run scripts/build.sh first" >&2; exit 1; }
[ -f "$DIST/dmg-bg.png" ] || { echo "error: dist/dmg-bg.png missing — run scripts/build.sh first" >&2; exit 1; }

echo "==> Staging"
rm -rf "$STAGE" "$RW_DMG"
mkdir -p "$STAGE/.background"
cp -R "$DIST/UseTokens.app" "$STAGE/UseTokens.app"
ln -s /Applications "$STAGE/Applications"
cp "$DIST/dmg-bg.png" "$STAGE/.background/dmg-bg.png"

# Unmount any stale volume from a previous run.
if [ -d "$VOL" ]; then hdiutil detach "$VOL" -force >/dev/null || true; fi

echo "==> Creating writable image (HFS+: reliable .DS_Store layout)"
hdiutil create -volname "UseTokens" -srcfolder "$STAGE" -format UDRW -fs HFS+ \
  -size 32m "$RW_DMG" >/dev/null

echo "==> Mounting"
hdiutil attach "$RW_DMG" -mountpoint "$VOL" >/dev/null
# From here on, any failure must not strand the mounted volume.
trap 'hdiutil detach "$VOL" -force >/dev/null 2>&1 || true' EXIT
sleep 1

echo "==> Styling with Finder (may prompt for Automation permission once)"
if ! osascript "$ROOT/scripts/dmg-layout.applescript"; then
  hdiutil detach "$VOL" -force >/dev/null || true
  echo "error: Finder styling failed (Automation permission denied? see note above)" >&2
  exit 1
fi

echo "==> Volume icon"
cp "$DIST/UseTokens.icns" "$VOL/.VolumeIcon.icns"
swift "$ROOT/scripts/set-volume-icon.swift" "$VOL" "$DIST/UseTokens.icns"

echo "==> Converting to compressed UDZO"
sync
# "Resource busy" right after mount is a known transient (Spotlight/Finder) — retry.
detached=0
for _ in 1 2 3 4 5; do
  if hdiutil detach "$VOL" >/dev/null 2>&1; then detached=1; break; fi
  sleep 2
done
[ "$detached" = 1 ] || hdiutil detach "$VOL" -force >/dev/null
trap - EXIT
mkdir -p "$(dirname "$OUT_DMG")"
rm -f "$OUT_DMG" # hdiutil convert refuses to overwrite
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" >/dev/null
rm -f "$RW_DMG"

hdiutil verify "$OUT_DMG" >/dev/null

# Sign and notarize the DMG itself: the quarantine flag lands on the file the
# user downloaded, so that is the one that has to carry a ticket.
"$ROOT/scripts/sign.sh" "$OUT_DMG" --notarize
echo "==> Built: $OUT_DMG ($(du -h "$OUT_DMG" | cut -f1))"

# Inside the nasmac.app monorepo this also publishes the release and refreshes
# the update manifest. From a standalone clone the DMG above is the output.
PUBLISH="$ROOT/../../scripts/publish-release.sh"
if [ -x "$PUBLISH" ]; then
  "$PUBLISH" "usetokens" "UseTokens" "$APP_VERSION" "$OUT_DMG" "${NOTES_PT:-}" "${NOTES_EN:-}"
fi
