#!/bin/bash
# Builds the install DMG: Remembrance.app beside an Applications link on a drawn background, with the
# app's icon as the volume icon. Usage: dmg/make-dmg.sh <Remembrance.app> <out.dmg>
# Needs Python 3 (dmgbuild is installed into a throwaway venv) and Xcode's swift and tiffutil.
set -euo pipefail
APP="$1"
OUT="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift "$HERE/background.swift" "$WORK"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null

python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install --quiet dmgbuild

ICON="$APP/Contents/Resources/AppIcon.icns"
ARGS=(-s "$HERE/settings.py" -D app="$APP" -D background="$WORK/background.tiff")
[ -f "$ICON" ] && ARGS+=(-D icon="$ICON")
rm -f "$OUT"
"$WORK/venv/bin/dmgbuild" "${ARGS[@]}" "Remembrance" "$OUT"
