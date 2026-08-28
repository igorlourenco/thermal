#!/bin/bash
# =============================================================================
# appcast.sh — regenerate the Sparkle feed from released DMGs.
#
# Flow per release:
#   1. bump CFBundleShortVersionString + CFBundleVersion in Resources/Info.plist
#   2. scripts/dmg.sh, copy dist/Thermal-<v>.dmg into dist/updates/
#   3. write release notes as dist/updates/Thermal-<v>.html (same basename as
#      the DMG; generate_appcast embeds it). Spec-styled template:
#      scripts/release-notes-template.html. Write user-visible changes, not
#      commits (installer.md §4).
#   4. scripts/appcast.sh   -> writes appcast.xml at the repo root
#   5. attach the DMG to the GitHub release for tag v<version>, then
#      scripts/appcast.sh --publish (commit + push appcast.xml)
#
# Signing uses the EdDSA key in the login Keychain (created once by
#   .build/artifacts/sparkle/Sparkle/bin/generate_keys
# and paired with SUPublicEDKey in Resources/Info.plist).
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

BIN=.build/artifacts/sparkle/Sparkle/bin
UPDATES=dist/updates

if [ ! -x "$BIN/generate_appcast" ]; then
    echo "Sparkle tools missing — run 'swift build' first." >&2
    exit 1
fi
if [ -z "$(ls "$UPDATES"/*.dmg 2>/dev/null)" ]; then
    echo "No DMGs in $UPDATES — copy released dist/Thermal-<v>.dmg files there." >&2
    exit 1
fi

# Newest release's assets live under its own tag. Older appcast entries keep
# this prefix too and may 404 — harmless, Sparkle only ever offers the newest.
NEWEST=$(ls "$UPDATES"/Thermal-*.dmg | sort -V | tail -1)
VERSION=$(basename "$NEWEST" .dmg | sed 's/^Thermal-//')
PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/igorlourenco/thermal/releases/download/v$VERSION/}"

# --embed-release-notes: the html goes into the appcast <description> itself,
# so nothing extra needs hosting.
"$BIN/generate_appcast" \
    --download-url-prefix "$PREFIX" \
    --embed-release-notes \
    -o appcast.xml \
    "$UPDATES"

echo "Wrote appcast.xml (newest: $VERSION, downloads: $PREFIX)"

# --publish: commit appcast.xml and push main. Shipped apps poll
# raw.githubusercontent.com/igorlourenco/thermal/main/appcast.xml, so the feed
# goes live the moment the push lands. Run this AFTER the DMG is on the release.
if [ "${1:-}" = "--publish" ]; then
    if git diff --quiet -- appcast.xml && git diff --cached --quiet -- appcast.xml; then
        echo "appcast.xml unchanged, nothing to publish"
        exit 0
    fi
    git add appcast.xml
    git commit -m "Appcast for $VERSION" -- appcast.xml
    git push origin HEAD:main
    echo "Published appcast.xml (newest: $VERSION)"
fi
