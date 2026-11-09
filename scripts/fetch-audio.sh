#!/bin/bash
# Downloads the four official Government of Canada recordings into audio/ (not committed; the
# build copies them into the app). Re-running skips files already present.
#
#   O Canada (instrumental)   Canadian Heritage   canada.ca/en/canadian-heritage/services/anthems-canada.html
#   God Save the King (instr.) Canadian Heritage   canada.ca/en/canadian-heritage/services/royal-symbols-titles/royal-anthem.html
#   Last Post, Rouse           Canadian Armed Forces canada.ca/en/services/defence/caf/showcasing/music/music-commemorative-ceremonies.html
#
# The hashes are the files as downloaded on Nov 9, 2026. A mismatch is only a warning: it means
# canada.ca replaced a recording, so listen to it before the service.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/audio"
BASE="https://www.canada.ca/content/dam"
mkdir -p "$DEST"

fetch() {
  local name="$1" path="$2" sha="$3"
  if [ ! -s "$DEST/$name" ]; then
    echo "Downloading $name"
    curl -fsSL --retry 3 -o "$DEST/$name.part" "$BASE/$path"
    mv "$DEST/$name.part" "$DEST/$name"
  fi
  local got
  got="$(shasum -a 256 "$DEST/$name" | awk '{print $1}')"
  if [ "$got" != "$sha" ]; then
    echo "warning: $name differs from the recording checked on Nov 9, 2026 (sha256 $got). Listen to it before the service." >&2
  fi
}

fetch o-canada.mp3     pch/audios/services/anthems-canada/O-Canada.mp3                           1a2f4908ea833b8b359c12d14820c4ae6eb2d4c713316fac009ee785f5cbb011
fetch last-post.wav    themes/defence/caf/militaryhistory/dhh/music/last-post-dernier-appel.wav 25e9af7d2d61cb6b8a42337093a4bf019c5c428e364ae6fab97ca5445331f594
fetch rouse.wav        themes/defence/caf/militaryhistory/dhh/music/rouse-reveille.wav           4e33c0382ba51e14f7044b825c7fd7d4259c2ac9b6cc144c2cf540c57ceffa24
fetch royal-anthem.mp3 pch/audios/services/royal-symbols-titles/reine-queen-eng.mp3              c9a707d4b3bb533eea0e72f5f15cc793f03c038c67bb9a1ce77cb2428da943c3
echo "Audio ready in $DEST"
