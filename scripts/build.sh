#!/bin/bash
# Builds the universal UseTokens.app into dist/.
#
# Signing is delegated to scripts/sign.sh, which explains the whole story:
# ad-hoc by default, Developer ID + notarization when DEVELOPER_ID and
# NOTARY_PROFILE are exported.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

# Single source of truth for the release version: stamped into the
# bundle here and published to the update manifest by dmg.sh.
APP_VERSION="${APP_VERSION:-1.0.1}"
DIST="$ROOT/dist"
APP="$DIST/UseTokens.app"

echo "==> Universal release build (per-arch: CLT has no xcbuild for --arch --arch)"
swift build -c release --triple arm64-apple-macosx13.0
swift build -c release --triple x86_64-apple-macosx13.0
BIN_ARM="$ROOT/.build/arm64-apple-macosx/release"
BIN_X86="$ROOT/.build/x86_64-apple-macosx/release"

mkdir -p "$DIST"
lipo -create "$BIN_ARM/UseTokens" "$BIN_X86/UseTokens" -output "$DIST/UseTokens-universal"
ARCHS="$(lipo -archs "$DIST/UseTokens-universal")"
if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
  echo "error: expected universal binary, got: $ARCHS" >&2
  exit 1
fi
# assetgen only runs on this machine — host arch is fine.
BIN_PATH="$BIN_ARM"

echo "==> Generating artwork (assetgen)"
mkdir -p "$DIST"
"$BIN_PATH/assetgen" icon "$DIST/icon-1024.png"
"$BIN_PATH/assetgen" dmg-background "$DIST/dmg-bg.png"
"$BIN_PATH/assetgen" web "$ROOT/../../www/assets"

echo "==> Building UseTokens.icns"
ICONSET="$DIST/UseTokens.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$DIST/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  if [ "$d" -eq 1024 ]; then
    cp "$DIST/icon-1024.png" "$ICONSET/icon_${s}x${s}@2x.png"
  else
    sips -z "$d" "$d" "$DIST/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  fi
done
iconutil -c icns "$ICONSET" -o "$DIST/UseTokens.icns"

echo "==> Assembling UseTokens.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$DIST/UseTokens-universal" "$APP/Contents/MacOS/UseTokens"
cp "$DIST/UseTokens.icns" "$APP/Contents/Resources/UseTokens.icns"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$APP_VERSION" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# The app is notarized here and the DMG again in dmg.sh: stapling both means
# the ticket travels with whichever file the user ends up double-clicking.
"$ROOT/scripts/sign.sh" "$APP" --notarize

echo "==> Done: $APP"
