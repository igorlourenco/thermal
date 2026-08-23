#!/bin/bash
# =============================================================================
# test-update.sh — see the installer.md §4 update dialog for real, locally.
#
#   scripts/test-update.sh             set it all up
#   scripts/test-update.sh --cleanup   undo everything
#
# What it does:
#   1. builds + installs the CURRENT version to /Applications (the "old" app)
#   2. builds a pretend NEXT version (patch bump, or NEXT_VERSION=x.y env)
#      into a DMG under dist/updates-test/
#   3. generates a signed appcast for it (EdDSA key from the login Keychain)
#   4. serves dist/updates-test/ on http://localhost:8000 and points the app
#      there via the ThermalFeedURLOverride default
#   5. launches Thermal — menu bar → Settings → "Check now" shows
#      "A new version of Thermal is available", release notes styled per spec.
#      Install actually replaces the app and relaunches it as the new version.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID=com.igorlourenco.thermal
PORT=8000
DIR=dist/updates-test
BIN=.build/artifacts/sparkle/Sparkle/bin

if [ "${1:-}" = "--cleanup" ]; then
    defaults delete "$BUNDLE_ID" ThermalFeedURLOverride 2> /dev/null || true
    pkill -f "http.server $PORT" 2> /dev/null || true
    rm -rf "$DIR"
    echo "Feed override removed, server stopped, $DIR deleted."
    exit 0
fi

# 1. Current version installed as the app that will receive the update.
killall thermal 2> /dev/null || true
scripts/bundle.sh --install
CUR=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" dist/Thermal.app/Contents/Info.plist)

# 2. Pretend next version: same build, bumped version strings, re-signed.
NEXT="${NEXT_VERSION:-$CUR.1}"
rm -rf "$DIR"
mkdir -p "$DIR"
cp -R dist/Thermal.app "$DIR/Thermal.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEXT" "$DIR/Thermal.app/Contents/Info.plist"
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$DIR/Thermal.app/Contents/Info.plist")
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "$DIR/Thermal.app/Contents/Info.plist"
codesign --force --sign - "$DIR/Thermal.app"

hdiutil create \
    -volname "Thermal $NEXT" \
    -srcfolder "$DIR/Thermal.app" \
    -format UDZO \
    -ov \
    "$DIR/Thermal-$NEXT.dmg" > /dev/null
rm -rf "$DIR/Thermal.app"

# 3. Spec-styled release notes + signed appcast.
sed -e "s/Thermal 1\.1/Thermal $NEXT/" \
    -e "s/May 12, 2026/$(date '+%b %-d, %Y')/" \
    scripts/release-notes-template.html > "$DIR/Thermal-$NEXT.html"

"$BIN/generate_appcast" \
    --download-url-prefix "http://localhost:$PORT/" \
    --embed-release-notes \
    -o "$DIR/appcast.xml" \
    "$DIR"

# 4. Serve it and point the installed app at it.
pkill -f "http.server $PORT" 2> /dev/null || true
(cd "$DIR" && nohup python3 -m http.server $PORT > /dev/null 2>&1 &)
defaults write "$BUNDLE_ID" ThermalFeedURLOverride "http://localhost:$PORT/appcast.xml"

# 5. Go.
open /Applications/Thermal.app
echo
echo "Thermal $CUR is running; the feed offers $NEXT."
echo "Menu bar → Settings → Check now. When done: scripts/test-update.sh --cleanup"
