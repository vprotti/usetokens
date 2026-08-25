#!/bin/bash
# Signs (and, when possible, notarizes) a .app or .dmg.
#
#   sign.sh <path> [--notarize]
#
# There is no free way to avoid Gatekeeper's "cannot verify this app is free of
# malware" dialog. It needs a Developer ID certificate, which needs the Apple
# Developer Program (USD 99/year). Ad-hoc and self-signed certificates do NOT
# help: on macOS 15+ a quarantined ad-hoc app is offered no "Open Anyway" at
# all, only "Move to Trash".
#
# So this script does the right thing at both levels:
#
#   unsigned     ->  ad-hoc, and says plainly that users will be blocked
#   DEVELOPER_ID ->  hardened runtime + secure timestamp (notarization-ready)
#   + NOTARY_PROFILE -> submits to Apple, waits, and staples the ticket
#
# To go from the first to the last:
#   1. developer.apple.com/programs — enrolling as an individual needs no
#      D-U-N-S and clears in about a day; a company (LTDA) needs a D-U-N-S
#      number and takes one to two weeks.
#   2. Download the "Developer ID Application" certificate into the login
#      keychain.
#   3. xcrun notarytool store-credentials nasralla \
#        --apple-id you@example.com --team-id TEAMID --password <app-specific>
#   4. export DEVELOPER_ID="Developer ID Application: Name (TEAMID)"
#      export NOTARY_PROFILE=nasralla
#
# Nothing else in the build has to change.
set -euo pipefail

TARGET="${1:?usage: sign.sh <path-to-.app-or-.dmg> [--notarize]}"
NOTARIZE=0
[ "${2:-}" = "--notarize" ] && NOTARIZE=1

if [ -z "${DEVELOPER_ID:-}" ]; then
  echo "==> Signing $(basename "$TARGET") ad-hoc (no DEVELOPER_ID set)"
  # Required on Apple Silicon: unsigned code will not run at all. It does not
  # satisfy Gatekeeper for a downloaded app — see the header.
  codesign --force --options runtime --sign - "$TARGET"
  codesign --verify --verbose=1 "$TARGET"
  echo "    note: downloads of this build are blocked by Gatekeeper until the"
  echo "          user removes the quarantine attribute. Set DEVELOPER_ID to fix."
  exit 0
fi

echo "==> Signing $(basename "$TARGET") as $DEVELOPER_ID"
# --timestamp needs the network; notarization rejects a signature without it.
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$TARGET"
codesign --verify --deep --strict --verbose=2 "$TARGET"

if ! codesign -dvv "$TARGET" 2>&1 | grep -q "^Timestamp="; then
  echo "error: signature has no secure timestamp — Apple will refuse it" >&2
  exit 1
fi

if [ "$NOTARIZE" != 1 ]; then exit 0; fi

if [ -z "${NOTARY_PROFILE:-}" ]; then
  echo "    skipping notarization: NOTARY_PROFILE not set"
  exit 0
fi

# A .app has to travel inside a container; a .dmg is already one.
SUBMIT="$TARGET"
CLEANUP=""
if [ "${TARGET##*.}" = "app" ]; then
  SUBMIT="${TARGET%.app}.notarize.zip"
  CLEANUP="$SUBMIT"
  ditto -c -k --keepParent "$TARGET" "$SUBMIT"
fi

echo "==> Notarizing (this waits on Apple, usually a few minutes)"
xcrun notarytool submit "$SUBMIT" --keychain-profile "$NOTARY_PROFILE" --wait
[ -n "$CLEANUP" ] && rm -f "$CLEANUP"

# Stapling puts the ticket inside the file, so it opens even offline.
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
echo "==> Notarized and stapled: $(basename "$TARGET")"
