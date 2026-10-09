#!/bin/zsh
# Converts a 1024x1024 PNG (e.g. an AI-generated icon) into Resources/AppIcon.icns.
# Usage: scripts/make-icns-from-png.sh path/to/icon-1024.png
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:?usage: make-icns-from-png.sh <png>}"
TMP="$(mktemp -d)"
mkdir -p "$TMP/AppIcon.iconset"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz "$SRC" --out "$TMP/AppIcon.iconset/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) "$SRC" --out "$TMP/AppIcon.iconset/icon_${sz}x${sz}@2x.png" >/dev/null
done
mkdir -p Resources
iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns from $SRC"
