#!/bin/bash
# =============================================================================
# dmg.sh — package dist/Thermal.app into the drag-to-Applications DMG from
# installer.md §2: 660×420 icon-view window, generated background art, volume
# icon, fixed icon positions. The window is the whole installer.
#
#   scripts/dmg.sh                 builds the .app (release) then the DMG
#
# Assets (background.tiff, VolumeIcon.icns, Thermal.icns) come from
# scripts/genassets.swift; regenerated here only if missing.
#
# The .DS_Store layout is written by dmgbuild (bootstrapped into a venv under
# .build/), not by scripting Finder — no Automation permission, runs headless.
# Verify by mounting on both a Retina and a non-Retina display.
#
# Distribution to other Macs additionally needs Developer ID signing +
# notarization (Gatekeeper blocks unsigned downloads):
#   SIGN_IDENTITY="Developer ID Application: ..." scripts/dmg.sh
#   xcrun notarytool submit dist/Thermal-<v>.dmg --keychain-profile <profile> --wait
#   xcrun stapler staple dist/Thermal-<v>.dmg
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

scripts/bundle.sh

if [ ! -f Resources/dmg/background.tiff ] || [ ! -f Resources/VolumeIcon.icns ]; then
    swift scripts/genassets.swift
fi

VENV=.build/dmg-venv
if [ ! -x "$VENV/bin/dmgbuild" ]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q dmgbuild
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" dist/Thermal.app/Contents/Info.plist)
DMG="dist/Thermal-$VERSION.dmg"

rm -f "$DMG"
"$VENV/bin/dmgbuild" \
    -s scripts/dmg_settings.py \
    -D app=dist/Thermal.app \
    "Thermal $VERSION" \
    "$DMG"

# Sign the DMG itself too when a real identity is available.
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "$SIGN_IDENTITY" "$DMG"
fi

echo "Built $DMG"
