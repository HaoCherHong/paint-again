#!/bin/zsh
# Builds, signs and packages the app for Mac App Store upload.
# Usage: scripts/package-appstore.sh
#
# Environment (all optional; without the signing material the script runs a dry run
# that produces an ad-hoc-signed app and an unsigned .pkg so the pipeline can be checked):
#   TEAM_ID               10-character Apple Team ID (adds the application-identifier /
#                         team-identifier entitlements the store requires)
#   APP_SIGN_IDENTITY     "Apple Distribution: Name (TEAMID)" (or "3rd Party Mac Developer Application: …")
#   PKG_SIGN_IDENTITY     "Mac Installer Distribution: Name (TEAMID)" (or "3rd Party Mac Developer Installer: …")
#   PROVISIONING_PROFILE  path to the Mac App Store .provisionprofile for the bundle ID
#   VERSION               CFBundleShortVersionString override (e.g. 1.0.0)
#   BUILD                 CFBundleVersion override (integer, must increase per upload)
#   ICON_FILE             Icon Composer .icon bundle (default: Resources/AppIcon.icon when present)
#
# Output: build/appstore/PaintAgain-<version>-<build>.pkg plus the signed "Paint Again.app" next to it.
set -euo pipefail
cd "$(dirname "$0")/.."

PB=/usr/libexec/PlistBuddy
OUT=build/appstore
APP="$OUT/Paint Again.app"
PLIST="$APP/Contents/Info.plist"
ICON_FILE="${ICON_FILE:-Resources/AppIcon.icon}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
PKG_SIGN_IDENTITY="${PKG_SIGN_IDENTITY:-}"
PROVISIONING_PROFILE="${PROVISIONING_PROFILE:-}"
TEAM_ID="${TEAM_ID:-}"

DRY_RUN=0
if [ -z "$APP_SIGN_IDENTITY" ] || [ -z "$PKG_SIGN_IDENTITY" ] || [ -z "$PROVISIONING_PROFILE" ] || [ -z "$TEAM_ID" ]; then
  DRY_RUN=1
  echo "== Dry run: missing one of TEAM_ID / APP_SIGN_IDENTITY / PKG_SIGN_IDENTITY / PROVISIONING_PROFILE."
  echo "   The app will be ad-hoc signed and the .pkg unsigned; neither can be uploaded."
fi

echo "== Building universal release"
PAINT_UNIVERSAL=1 scripts/build.sh release
rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "build/Paint Again.app" "$APP"

echo "== Stamping Info.plist"
if [ -n "${VERSION:-}" ]; then $PB -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"; fi
if [ -n "${BUILD:-}" ]; then $PB -c "Set :CFBundleVersion $BUILD" "$PLIST"; fi
XCODE_VERSION="$(xcodebuild -version | awk '/^Xcode/ {print $2}')"
XCODE_BUILD="$(xcodebuild -version | awk '/^Build version/ {print $3}')"
DTXCODE="$(echo "$XCODE_VERSION" | awk -F. '{printf "%02d%d%d", $1, $2, ($3 == "" ? 0 : $3)}')"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
SDK_BUILD="$(xcrun --sdk macosx --show-sdk-build-version)"
set_key() { $PB -c "Delete :$1" "$PLIST" >/dev/null 2>&1 || true; $PB -c "Add :$1 $2 $3" "$PLIST"; }
set_key DTXcode string "$DTXCODE"
set_key DTXcodeBuild string "$XCODE_BUILD"
set_key DTSDKName string "macosx$SDK_VERSION"
set_key DTSDKBuild string "$SDK_BUILD"
set_key DTPlatformName string macosx
set_key DTPlatformVersion string "$SDK_VERSION"
set_key DTPlatformBuild string "$SDK_BUILD"
set_key DTCompiler string com.apple.compilers.llvm.clang.1_0
set_key BuildMachineOSBuild string "$(sw_vers -buildVersion)"

if [ -d "$ICON_FILE" ]; then
  echo "== Compiling $ICON_FILE with actool"
  ACTOOL_PLIST="$OUT/actool-partial.plist"
  xcrun actool "$ICON_FILE" --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target "$($PB -c 'Print :LSMinimumSystemVersion' "$PLIST")" \
    --app-icon AppIcon --include-all-app-icons \
    --output-partial-info-plist "$ACTOOL_PLIST" >/dev/null
  $PB -c "Merge $ACTOOL_PLIST" "$PLIST"
else
  echo "== No Icon Composer bundle at $ICON_FILE; shipping AppIcon.icns only"
fi

if [ -n "$PROVISIONING_PROFILE" ]; then
  echo "== Embedding provisioning profile"
  cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
fi

echo "== Signing"
# Quarantine / Finder-info attributes would fail codesign; com.apple.provenance survives this and is harmless.
xattr -cr "$APP"
ENTITLEMENTS="$OUT/Paint-dist.entitlements"
cp Paint.entitlements "$ENTITLEMENTS"
BUNDLE_ID="$($PB -c 'Print :CFBundleIdentifier' "$PLIST")"
if [ -n "$TEAM_ID" ]; then
  $PB -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" "$ENTITLEMENTS"
  $PB -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ENTITLEMENTS"
fi
SIGN_ARGS=(--force --options runtime --entitlements "$ENTITLEMENTS")
RESOURCE_BUNDLE="$APP/Contents/Resources/Paint_Paint.bundle"
if [ "$DRY_RUN" = 1 ]; then
  [ -d "$RESOURCE_BUNDLE" ] && codesign --force --sign - "$RESOURCE_BUNDLE"
  codesign "${SIGN_ARGS[@]}" --sign - "$APP"
else
  [ -d "$RESOURCE_BUNDLE" ] && codesign --force --timestamp --sign "$APP_SIGN_IDENTITY" "$RESOURCE_BUNDLE"
  codesign "${SIGN_ARGS[@]}" --timestamp --sign "$APP_SIGN_IDENTITY" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

echo "== Building installer package"
NAME="$($PB -c 'Print :CFBundleName' "$PLIST")"
VER="$($PB -c 'Print :CFBundleShortVersionString' "$PLIST")"
BLD="$($PB -c 'Print :CFBundleVersion' "$PLIST")"
PKG="$OUT/${NAME// /}-$VER-$BLD.pkg"
if [ "$DRY_RUN" = 1 ]; then
  productbuild --component "$APP" /Applications "$PKG" >/dev/null
else
  productbuild --component "$APP" /Applications --sign "$PKG_SIGN_IDENTITY" "$PKG" >/dev/null
  pkgutil --check-signature "$PKG"
fi

echo
echo "Packaged $PKG"
codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -p - 2>/dev/null || true
if [ "$DRY_RUN" = 1 ]; then
  echo "Dry run only — set TEAM_ID, APP_SIGN_IDENTITY, PKG_SIGN_IDENTITY and PROVISIONING_PROFILE for a store build."
else
  cat <<MSG
Next:
  xcrun altool --validate-app -f "$PKG" --type macos --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
  xcrun altool --upload-app  -f "$PKG" --type macos --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
or drop the .pkg on Transporter.
MSG
fi
