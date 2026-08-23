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

BINARY=".build/$CONFIG/thermal"
APP="dist/Thermal.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/thermal"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Sparkle.framework (updates, installer.md §4). The binary's rpath points at
# ../Frameworks (set in Package.swift); SwiftPM's artifact checkout has the
# actual framework.
SPARKLE=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
    mkdir -p "$APP/Contents/Frameworks"
    cp -R "$SPARKLE" "$APP/Contents/Frameworks/"
else
    echo "warning: Sparkle.framework not found at $SPARKLE — updates won't work" >&2
fi

# App icon, once one exists.
if [ -f Resources/Thermal.icns ]; then
    cp Resources/Thermal.icns "$APP/Contents/Resources/Thermal.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Thermal" "$APP/Contents/Info.plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile Thermal" "$APP/Contents/Info.plist"
fi

# Ad-hoc signature is enough for local use (notifications, launch-at-login);
# Sparkle ships pre-signed by its project and can keep that signature. For
# distribution (Developer ID + notarization), Sparkle's nested code must be
# re-signed with our identity and the hardened runtime, inside-out.
if [ -n "${SIGN_IDENTITY:-}" ]; then
    FW="$APP/Contents/Frameworks/Sparkle.framework"
    if [ -d "$FW" ]; then
        codesign -f -s "$SIGN_IDENTITY" -o runtime "$FW/Versions/B/XPCServices/Installer.xpc"
        codesign -f -s "$SIGN_IDENTITY" -o runtime --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
        codesign -f -s "$SIGN_IDENTITY" -o runtime "$FW/Versions/B/Autoupdate"
        codesign -f -s "$SIGN_IDENTITY" -o runtime "$FW/Versions/B/Updater.app"
        codesign -f -s "$SIGN_IDENTITY" -o runtime "$FW"
    fi
    codesign --force --sign "$SIGN_IDENTITY" -o runtime "$APP"
else
    codesign --force --sign - "$APP"
fi

echo "Built $APP"

if $INSTALL; then
    rm -rf "/Applications/Thermal.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/Thermal.app"
fi
