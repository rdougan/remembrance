#!/bin/bash
# Builds build/Remembrance.app: compiles with SwiftPM, then assembles the bundle with the icon and
# the four recordings (downloaded by fetch-audio.sh if missing). Works with just the Command Line
# Tools; with full Xcode (CI) pass UNIVERSAL=1 for an arm64 + x86_64 binary.
#
# Usage: scripts/build-app.sh [version] [build-number]
#   SIGN_IDENTITY=<Developer ID hash>  sign for release (hardened runtime); default is ad-hoc.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(tr -d '[:space:]' < "$ROOT/VERSION").0}"
BUILD="${2:-0}"
APP="$ROOT/build/Remembrance.app"
cd "$ROOT"

bash scripts/fetch-audio.sh

if [ "${UNIVERSAL:-0}" = 1 ]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Remembrance"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/Remembrance"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Remembrance"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp audio/o-canada.mp3 audio/last-post.wav audio/rouse.wav audio/royal-anthem.mp3 "$APP/Contents/Resources/"

ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION, build $BUILD)"
