#!/bin/zsh
# Re-signs "build/Paint Again.app" with Paint.entitlements so it runs inside the App Sandbox
# exactly as the Mac App Store build will. Run scripts/build.sh first.
# Usage: scripts/sign-sandboxed.sh [codesign identity]   (default "-" = ad-hoc)
#
# With the ad-hoc identity the app launches locally and the sandbox is enforced
# (container at ~/Library/Containers/com.haocherhong.paintagain). Pass an
# "Apple Development: …" identity to test with a real certificate.
set -euo pipefail
cd "$(dirname "$0")/.."
IDENTITY="${1:--}"
APP="build/Paint Again.app"
[ -d "$APP" ] || { echo "$APP missing — run scripts/build.sh first" >&2; exit 1; }
codesign --force --sign "$IDENTITY" --entitlements Paint.entitlements --options runtime "$APP"
codesign --verify --strict --verbose=1 "$APP"
echo "Signed $APP (sandboxed, identity: $IDENTITY)"
codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -p - 2>/dev/null || codesign -d --entitlements - "$APP"
