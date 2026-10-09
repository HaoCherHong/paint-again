#!/bin/zsh
# Builds Resources/AppIcon.icns from transparent glyph layers (see docs/paint-mac/ICON_PROMPT.md).
# Usage: scripts/compose-legacy-icon.sh <layer.png> [more layers…]     env ICON_TOP / ICON_BOTTOM override the tile gradient.
# Also writes Resources/icon-legacy-1024.png for review.
set -euo pipefail
cd "$(dirname "$0")/.."
[ $# -ge 1 ] || { echo "usage: compose-legacy-icon.sh <layer.png> [more layers…]" >&2; exit 1; }
TMP="$(mktemp -d)"
swiftc -O -o "$TMP/compose" scripts/compose-legacy-icon.swift
"$TMP/compose" Resources/icon-legacy-1024.png "$@"
scripts/make-icns-from-png.sh Resources/icon-legacy-1024.png
rm -rf "$TMP"
