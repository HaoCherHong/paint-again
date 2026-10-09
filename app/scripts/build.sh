#!/bin/zsh
# Builds the Swift package and assembles "build/Paint Again.app" (executable stays Paint).
# The result is ad-hoc signed and not sandboxed; see scripts/sign-sandboxed.sh.
# Usage: scripts/build.sh [debug|release]
#   PAINT_UNIVERSAL=1   build an arm64 + x86_64 binary (release packaging)
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
ARCH_FLAGS=()
if [ "${PAINT_UNIVERSAL:-0}" = "1" ]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)"
APP="build/Paint Again.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Paint" "$APP/Contents/MacOS/Paint"
cp Info.plist "$APP/Contents/Info.plist"
cp PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
if [ -d "$BIN_DIR/Paint_Paint.bundle" ]; then
  cp -R "$BIN_DIR/Paint_Paint.bundle" "$APP/Contents/Resources/"
  # SwiftPM writes CFBundleExecutable into the resource bundle although it has no binary;
  # App Store validation rejects that (ITMS-90261).
  for plist in "$APP/Contents/Resources/Paint_Paint.bundle/Contents/Info.plist" "$APP/Contents/Resources/Paint_Paint.bundle/Info.plist"; do
    [ -f "$plist" ] && /usr/libexec/PlistBuddy -c "Delete :CFBundleExecutable" "$plist" >/dev/null 2>&1 || true
  done
fi
if [ -f "Resources/AppIcon.icns" ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
