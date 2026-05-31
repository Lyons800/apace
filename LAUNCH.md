# Murmur — Launch Runbook

Status as of 2026-05-31. This is the checklist to take Murmur from "feature-complete on my Mac" to "downloadable, signed, auto-updating public app."

## TL;DR — the critical path

1. **Enrol in the paid Apple Developer Program** (the one true blocker). → §1
2. **Create a Developer ID Application certificate** + export it as `.p12`. → §2
3. **Create an app-specific password** for notarization. → §2
4. **Confirm the real Team ID** and fix it in the Xcode project. → §3
5. **Add 4 GitHub Actions secrets.** → §4
6. **Tag a release** → CI builds, signs, notarizes, publishes. → §5
7. **Verify** the DMG + auto-update + site download work. → §6

Everything below §1 is blocked until enrolment is approved.

---

## What's already done ✅

- App is feature-complete (`Murmur.app`, bundle `dev.murmur.app`, repo `Lyons800/murmur` — public).
- Sparkle auto-update is wired in. EdDSA **public** key is in the app; **private** key is in the Mac keychain *and* in GitHub secret `SPARKLE_EDDSA_PRIVATE_KEY`.
- `.github/workflows/release.yml` — full CI release pipeline, fires on a `v*` tag.
- `Scripts/notarize.sh` — local notarization fallback.
- `homebrew-murmur/Casks/murmur.rb` — Homebrew cask (secondary channel).
- Landing site (`../murmur-site`) is live at **murmur.dev**.
- **Fixed 2026-05-31:** every `oisinlyons/murmur` URL corrected to `Lyons800/murmur` — this includes the app's Sparkle feed URL (`INFOPLIST_KEY_SUFeedURL`, both build configs), the cask, and all 5 site links. A shipped app would otherwise have checked for updates at a dead URL.

---

## §1 — Enrol in the Apple Developer Program  ⛔ BLOCKER

Your Mac currently has only an **"Apple Development"** certificate. That signs apps for local testing but **cannot** be used to distribute outside the Mac App Store. You need a **"Developer ID Application"** certificate, which requires paid membership.

1. Go to https://developer.apple.com/programs/enroll/
2. Sign in with `oisinlyons13@gmail.com` (the Apple ID already on this Mac).
3. Enrol as an **Individual** (simplest; the app ships under your name) or **Organization** (needs a D-U-N-S number; ships under a company name). Individual is the fast path.
4. Pay **$99/yr**. Approval is usually minutes–hours, occasionally up to 48h.

> Decision needed if you go Organization: that requires a D-U-N-S number and can take days. Recommend Individual to launch fast; you can migrate later.

---

## §2 — Create the Developer ID cert + notary password  (after §1 approved)

**Developer ID Application certificate:**
1. Xcode → Settings → Accounts → your Apple ID → **Manage Certificates…**
2. Click **+** → **Developer ID Application**. (Or create at https://developer.apple.com/account/resources/certificates/list)
3. Export for CI: Keychain Access → find "Developer ID Application: …" → right-click → **Export** → save as `certificate.p12`, set a strong password (you'll need it as a secret). Keep this file OUT of git (`.p12` is already gitignored).

**App-specific password (for notarization):**
1. https://account.apple.com → Sign-In and Security → **App-Specific Passwords** → generate one, label it "murmur-notary".
2. Save the generated password — it's the `APPLE_APP_PASSWORD` secret.

---

## §3 — Confirm and fix the Team ID  ⚠️ MISMATCH

There are **two** Team IDs in play and they don't match:

| Source | Team ID |
|---|---|
| Xcode project (`DEVELOPMENT_TEAM`, ×8 in `project.pbxproj`) | `BWD692VD35` |
| Your local "Apple Development" cert (`oisinlyons13@gmail.com`) | `MDY7H22G36` |

`BWD692VD35` looks stale/placeholder; `MDY7H22G36` is your personal team. When you enrol as an Individual, your paid Team ID is almost always your existing personal team (likely `MDY7H22G36`).

**To confirm:** https://developer.apple.com/account → **Membership details** → copy the **Team ID**.

**Then fix it** (replace `MDY7H22G36` below with the confirmed value if different):
```bash
cd ~/Projects/GitHub/Active/WhisprMacOS
sed -i '' 's/BWD692VD35/MDY7H22G36/g' WhisprMacOS.xcodeproj/project.pbxproj
grep -c MDY7H22G36 WhisprMacOS.xcodeproj/project.pbxproj   # expect 8
```
Also confirm the GitHub secret `APPLE_TEAM_ID` (already set) equals the same value:
```bash
# can't read secret values; re-set to be sure:
gh secret set APPLE_TEAM_ID -R Lyons800/murmur --body "MDY7H22G36"
```

---

## §4 — Add the GitHub Actions secrets

Already set: `APPLE_TEAM_ID`, `SPARKLE_EDDSA_PRIVATE_KEY`.
**Still missing (release CI will fail without these):**

```bash
cd ~/Projects/GitHub/Active/WhisprMacOS
# base64 the exported cert and store it
gh secret set APPLE_CERTIFICATE_P12 -R Lyons800/murmur < <(base64 -i ~/path/to/certificate.p12)
gh secret set APPLE_CERTIFICATE_PASSWORD -R Lyons800/murmur --body "<p12 export password>"
gh secret set APPLE_ID -R Lyons800/murmur --body "oisinlyons13@gmail.com"
gh secret set APPLE_APP_PASSWORD -R Lyons800/murmur --body "<app-specific password from §2>"

gh secret list -R Lyons800/murmur   # expect 6 secrets total
```

---

## §5 — Cut the first release

```bash
cd ~/Projects/GitHub/Active/WhisprMacOS
git add -A && git commit -m "Launch prep: fix update feed URL + team ID"
# bump marketing version to match the tag (currently 1.0):
#   Xcode → target → General → Version = 1.0.0  (or edit MARKETING_VERSION in pbxproj)
git tag v1.0.0
git push origin main --tags
```
The tag push triggers `.github/workflows/release.yml`, which: builds → signs (Developer ID) → creates DMG → **notarizes + staples** → Sparkle-signs → generates `appcast.xml` → publishes a GitHub Release with `Murmur.dmg` + `appcast.xml` attached.

Watch it: `gh run watch -R Lyons800/murmur`

---

## §6 — Verify the launch

- **Download:** the site's "Download Free" buttons point to `github.com/Lyons800/murmur/releases/latest` — confirm it resolves to the DMG once the release exists.
- **Gatekeeper:** on a *different* Mac (or after removing your dev signing), download the DMG and open `Murmur.app` — it should open with **no** "unidentified developer" warning. If it warns, notarization didn't staple.
  - Check: `spctl -a -t open --context context:primary-signature -v ~/Downloads/Murmur.dmg`
  - Check: `xcrun stapler validate ~/Downloads/Murmur.dmg`
- **Auto-update:** install an older build, then confirm Sparkle sees the new release at the feed URL.
- **Homebrew (optional):** the cask still has `sha256 "REPLACE_WITH_DMG_SHA256"`. After the release, set it:
  `shasum -a 256 Murmur.dmg` → paste into `homebrew-murmur/Casks/murmur.rb`, bump `version` to `1.0.0`, and publish the tap as repo `Lyons800/homebrew-murmur` so users can `brew install --cask lyons800/murmur/murmur`.

---

## Known minor issues (non-blocking)

- `release.yml`: the Sparkle `sign_update` output (`sparkle:edSignature="…" length="…"`) is injected into an `<enclosure>` that already has a `length` attribute → duplicate `length`. Sparkle tolerates it, but worth cleaning up.
- Cask `version` is `1.0.0` while the app's `MARKETING_VERSION` is `1.0` — align them at release.
- The release workflow does **not** auto-update the Homebrew cask's `sha256`; do it manually (§6) or add a step later.
- Site: Pro tier ($29, Paddle) is advertised but the purchase flow isn't wired. Free DMG download works independently, so this doesn't block launch — wire Paddle before charging.
