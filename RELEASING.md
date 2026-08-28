# Releasing Thermal

Ship path: signed + notarized DMG attached to a GitHub release, Sparkle feed
(`appcast.xml`) at the root of `main`. Installed apps check the feed daily and
auto-install (or Settings → Check now).

Everything lives in one public repo, `igorlourenco/thermal` (remote `origin`):
source, `appcast.xml`, README, and the DMGs as release assets.

Public endpoints (baked into shipped builds, don't move them casually):

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

3. **Back up the Sparkle EdDSA key**. It lives only in this Mac's login
   Keychain; losing it strands every installed copy (they'd reject any future
   update):

   ```bash
   .build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/thermal-sparkle-key-BACKUP
   ```

   Store that file somewhere safe and private, never in the repo. Its public
   half is `SUPublicEDKey` in `Resources/Info.plist`.

## Every release

```bash
# 1. bump BOTH versions in Resources/Info.plist
#    CFBundleShortVersionString  1.2 -> 1.3   (what users see)
#    CFBundleVersion             3   -> 4     (what Sparkle compares)

# 2. build, sign, notarize, staple (paste your exact identity from step 1 above)
SIGN_IDENTITY="Developer ID Application: Igor Lourenco (P73HCK6SHJ)" scripts/dmg.sh
xcrun notarytool submit dist/Thermal-1.3.dmg --keychain-profile thermal --wait
xcrun stapler staple dist/Thermal-1.3.dmg

# 3. feed entry: DMG + release notes into dist/updates/ (kept across releases,
#    git-ignored), then regenerate the appcast
mkdir -p dist/updates
cp dist/Thermal-1.3.dmg dist/updates/
cp scripts/release-notes-template.html dist/updates/Thermal-1.3.html  # then EDIT it:
#    user-visible changes, not commits
scripts/appcast.sh

# 4. commit the release, tag it, push
git add -A && git commit -m "Release 1.3" && git tag v1.3 && git push origin main v1.3

# 5. DMG onto the release FIRST, then publish the feed
#    (never point the feed at a download that isn't live yet)
gh release create v1.3 dist/Thermal-1.3.dmg --title "Thermal 1.3" --notes "See in-app release notes."
scripts/appcast.sh --publish     # commits appcast.xml and pushes main
```

Sparkle deltas (`Thermal<build>-<prev>.delta`) are generated next to the DMG in
`dist/updates/`; upload them to the same release with `gh release upload v1.3
dist/updates/Thermal4-*.delta` (this build number) so auto-updates stay small.

First install: send the DMG (or the release link). They drag to Applications,
Gatekeeper shows the notarized **Open** alert once (installer.md §3), and every
later release you publish reaches them automatically.

Local end-to-end rehearsal without touching production: `scripts/test-update.sh`.
Download counts per asset: `scripts/stats.sh`.
