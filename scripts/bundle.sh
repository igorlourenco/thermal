#!/bin/bash
# =============================================================================
# bundle.sh — assemble Thermal.app from the SwiftPM build.
#
#   scripts/bundle.sh              release build -> dist/Thermal.app, ad-hoc signed
#   scripts/bundle.sh --debug      debug build (faster, for iterating)
#   scripts/bundle.sh --install    also copy to /Applications (replaces existing)
#   SIGN_IDENTITY="Developer ID Application: ..." scripts/bundle.sh
#                                  sign with a real identity instead of ad-hoc
#
# SwiftPM stays the only build system; this just wraps the binary in the
# .app structure that unlocks notifications, launch-at-login and an icon.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG=release
INSTALL=false
for arg in "$@"; do
    case "$arg" in
        --debug) CONFIG=debug ;;
        --install) INSTALL=true ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

echo "Building ($CONFIG)…"
swift build -c "$CONFIG"

BINARY=".build/$CONFIG/tempsensors"
APP="dist/Thermal.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/tempsensors"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon, once one exists.
if [ -f Resources/Thermal.icns ]; then
    cp Resources/Thermal.icns "$APP/Contents/Resources/Thermal.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Thermal" "$APP/Contents/Info.plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile Thermal" "$APP/Contents/Info.plist"
fi

# Ad-hoc signature is enough for local use (notifications, launch-at-login).
# Distribution needs a Developer ID + notarization: set SIGN_IDENTITY.
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"

echo "Built $APP"

if $INSTALL; then
    rm -rf "/Applications/Thermal.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/Thermal.app"
fi
