#!/bin/sh
# Build a drag-to-Applications DMG with the crafting table background.
# Uses dmgbuild, which writes the Finder layout without driving Finder,
# so it works on headless CI runners.
#
#   scripts/make-dmg.sh path/to/AppleSign.app out.dmg
set -e
APP=$1
OUT=$2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VENV=$ROOT/.cache/venv
WORK=$ROOT/build/dmg

if [ ! -x "$VENV/bin/dmgbuild" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet dmgbuild
fi

rm -rf "$WORK"
mkdir -p "$WORK" "$(dirname "$OUT")"
swift "$ROOT/scripts/render-art.swift" dmg "$WORK"
tiffutil -cathidpicheck "$WORK/dmg-background.png" "$WORK/dmg-background@2x.png" \
  -out "$WORK/background.tiff"

rm -f "$OUT"
"$VENV/bin/dmgbuild" -s "$ROOT/scripts/dmg-settings.py" \
  -D app="$APP" -D background="$WORK/background.tiff" "AppleSign" "$OUT"
echo "[+] $OUT"
