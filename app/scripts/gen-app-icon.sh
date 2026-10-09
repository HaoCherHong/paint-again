#!/bin/zsh
# Regenerates Resources/AppIcon.icns from scripts/gen-app-icon.swift (the single source of the icon).
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
swiftc -O -o "$TMP/mkicon" scripts/gen-app-icon.swift
"$TMP/mkicon" "$TMP/icon1024.png"
mkdir -p "$TMP/AppIcon.iconset"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz "$TMP/icon1024.png" --out "$TMP/AppIcon.iconset/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) "$TMP/icon1024.png" --out "$TMP/AppIcon.iconset/icon_${sz}x${sz}@2x.png" >/dev/null
done
mkdir -p Resources
iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns"
