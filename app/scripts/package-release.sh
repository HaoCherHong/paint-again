#!/bin/zsh
# Builds, signs, notarises and zips the app for a GitHub release (direct download).
# Usage: scripts/package-release.sh
#
# Environment (without the signing material the script runs a dry run that produces an
# ad-hoc-signed, un-notarised zip so the pipeline can be checked; never publish that one):
#   DEVELOPER_ID          "Developer ID Application: Name (TEAMID)"
#   NOTARY_PROFILE        notarytool keychain profile, created once with
#                         xcrun notarytool store-credentials <profile> --apple-id … --team-id …
#   VERSION               CFBundleShortVersionString override (e.g. 1.1.0)
#   BUILD                 CFBundleVersion override
#
# Output: build/release/PaintAgain.zip and PaintAgain.zip.sha256. The name carries no version so
# that https://github.com/HaoCherHong/paint-again/releases/latest/download/PaintAgain.zip always
# serves the newest release (the website's download button links there); the release tag carries it.
# The app runs in the App Sandbox with the same entitlements as the store build.
set -euo pipefail
cd "$(dirname "$0")/.."

PB=/usr/libexec/PlistBuddy
OUT=build/release
APP="$OUT/Paint Again.app"
PLIST="$APP/Contents/Info.plist"
DEVELOPER_ID="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

DRY_RUN=0
if [ -z "$DEVELOPER_ID" ] || [ -z "$NOTARY_PROFILE" ]; then
  DRY_RUN=1
  echo "== Dry run: missing DEVELOPER_ID or NOTARY_PROFILE."
  echo "   The app will be ad-hoc signed and not notarised; Gatekeeper will block it on other Macs."
fi

echo "== Building universal release"
PAINT_UNIVERSAL=1 scripts/build.sh release
rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "build/Paint Again.app" "$APP"

if [ -n "${VERSION:-}" ]; then $PB -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"; fi
if [ -n "${BUILD:-}" ]; then $PB -c "Set :CFBundleVersion $BUILD" "$PLIST"; fi
VER="$($PB -c 'Print :CFBundleShortVersionString' "$PLIST")"
ZIP="$OUT/PaintAgain.zip"

echo "== Signing"
xattr -cr "$APP"
SIGN_ARGS=(--force --options runtime --entitlements Paint.entitlements)
RESOURCE_BUNDLE="$APP/Contents/Resources/Paint_Paint.bundle"
if [ "$DRY_RUN" = 1 ]; then
  [ -d "$RESOURCE_BUNDLE" ] && codesign --force --sign - "$RESOURCE_BUNDLE"
  codesign "${SIGN_ARGS[@]}" --sign - "$APP"
else
  [ -d "$RESOURCE_BUNDLE" ] && codesign --force --timestamp --sign "$DEVELOPER_ID" "$RESOURCE_BUNDLE"
  codesign "${SIGN_ARGS[@]}" --timestamp --sign "$DEVELOPER_ID" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

if [ "$DRY_RUN" = 0 ]; then
  echo "== Notarising"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
  rm -f "$ZIP"
fi

echo "== Zipping"
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$OUT" && shasum -a 256 "${ZIP:t}" > "${ZIP:t}.sha256")

echo
echo "Packaged $ZIP"
cat "$ZIP.sha256"
if [ "$DRY_RUN" = 1 ]; then
  echo "Dry run only — set DEVELOPER_ID and NOTARY_PROFILE for a release build."
else
  cat <<MSG
Next (from the repo root, after tagging v$VER on main):
  gh release create v$VER "app/$ZIP" "app/$ZIP.sha256" --title "Paint Again $VER" --notes-file <notes.md>
MSG
fi
