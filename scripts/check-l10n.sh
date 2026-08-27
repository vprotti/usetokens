#!/bin/bash
# Every key the code asks L10n for has to exist in L10n's table.
#
# A missing one does not crash and does not warn: L10n.t returns the key it was
# given, so the app ships and shows a real person "settings.launchAtLogin" where
# a label should be. That is exactly what happened, in the Settings window, for
# a whole release. This makes it a build failure instead.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)/Sources"

SRC="$SRC" python3 - <<'PY'
import glob, os, re, sys

src = os.environ["SRC"]
files = glob.glob(os.path.join(src, "*", "*.swift"))
table = [f for f in files if os.path.basename(f) == "L10n.swift"]
if not table:
    sys.exit(0)                       # no localization in this app, nothing to check

defined = set()
for f in table:
    defined |= set(re.findall(r'^\s*"([^"]+)":\s*\(', open(f).read(), re.M))

used = {}
for f in files:
    for line, text in enumerate(open(f), 1):
        for key in re.findall(r'L10n\.t\("([^"]+)"', text):
            used.setdefault(key, (os.path.relpath(f, src), line))
        # A note key is handed to L10n.t later, by whoever draws the card.
        for key in re.findall(r'noteKey: "([^"]+)"', text):
            used.setdefault(key, (os.path.relpath(f, src), line))

missing = sorted(k for k in used if k not in defined)
if missing:
    print("missing from L10n.swift:", file=sys.stderr)
    for key in missing:
        where, line = used[key]
        print(f"  {key}  ({where}:{line})", file=sys.stderr)
    sys.exit(1)

print(f"    l10n: {len(used)} keys, all present")
PY
