# Releasing Thermal

Ship path: signed + notarized DMG on a GitHub release, Sparkle feed committed
to `main`. Installed apps check the feed daily and auto-install (or Settings →
Check now).

Public endpoints (baked into shipped builds — don't move them casually):

- Feed: `https://raw.githubusercontent.com/igorlourenco/thermal/main/appcast.xml`
- Downloads: `https://github.com/igorlourenco/thermal/releases/download/v<version>/Thermal-<version>.dmg`

## One-time setup

1. **Developer ID certificate** (needs the paid Apple Developer Program):
   Xcode → Settings → Accounts → team `P73HCK6SHJ` → Manage Certificates →
   `+` → **Developer ID Application**. Verify:

   ```bash
   security find-identity -v -p codesigning | grep "Developer ID"
   ```

2. **Notary credentials**: create an app-specific password at
   https://account.apple.com → Sign-In and Security, then:

   ```bash
   xcrun notarytool store-credentials thermal \
       --apple-id <your-apple-id> --team-id P73HCK6SHJ --password <app-specific-pw>
   ```

3. **Back up the Sparkle EdDSA key** — it lives only in this Mac's login
   Keychain; losing it strands every installed copy (they'd reject any future
   update):

   ```bash
   .build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/thermal-sparkle-key-BACKUP
   ```

   Store that file somewhere safe and private. Its public half is
   `SUPublicEDKey` in `Resources/Info.plist`.

## Every release

```bash
# 1. bump BOTH versions in Resources/Info.plist
#    CFBundleShortVersionString  1.0 -> 1.1   (what users see)
#    CFBundleVersion             1   -> 2     (what Sparkle compares)

# 2. build, sign, notarize, staple (paste your exact identity from step 1 above)
SIGN_IDENTITY="Developer ID Application: Igor Lourenco (P73HCK6SHJ)" scripts/dmg.sh
xcrun notarytool submit dist/Thermal-1.1.dmg --keychain-profile thermal --wait
xcrun stapler staple dist/Thermal-1.1.dmg

# 3. feed entry: DMG + release notes into dist/updates/ (kept across releases,
#    git-ignored), then regenerate the appcast
mkdir -p dist/updates
cp dist/Thermal-1.1.dmg dist/updates/
cp scripts/release-notes-template.html dist/updates/Thermal-1.1.html  # then EDIT it:
#    user-visible changes, not commits (installer.md §4)
scripts/appcast.sh

# 4. publish — appcast on main, DMG on the release
git add appcast.xml && git commit -m "Release 1.1" && git push
gh release create v1.1 dist/Thermal-1.1.dmg --title "Thermal 1.1" --notes "See in-app release notes."
```

First install: send the DMG (or the release link). They drag to Applications,
Gatekeeper shows the notarized **Open** alert once (installer.md §3), and every
later release you publish reaches them automatically.

Local end-to-end rehearsal without touching production: `scripts/test-update.sh`.
