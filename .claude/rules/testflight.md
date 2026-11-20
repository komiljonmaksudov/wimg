# TestFlight — wimg iOS

> **Local Xcode archives no longer work.** Apple requires iOS 26 SDK
> (Xcode 26 + macOS 26) for all App Store Connect uploads. Builds now run
> on GitHub Actions `macos-26` runners — see [`ci-testflight.md`](ci-testflight.md).

## Prerequisites

- Apple Developer account (paid, $99/year)
- App registered in App Store Connect (Bundle ID: `com.wimg.app`)
- App Store Connect API key configured as GitHub secrets — see `ci-testflight.md`

## Upload a New Build (via CI)

1. Run `./scripts/release.sh patch --push` (bumps `MARKETING_VERSION` together
   with the Android `versionName`, tags, pushes). CI sets
   `CURRENT_PROJECT_VERSION` to a Unix timestamp on every build.
2. Wait ~10-15 min for CI to archive + upload, then another 5-15 min for
   Apple to process the build.
3. App Store Connect → TestFlight → your test group → Builds → **+** → select
   the new build.

## First-Time Setup (already done)

1. Register Bundle ID at developer.apple.com/account/resources/identifiers
2. Create app in App Store Connect (appstoreconnect.apple.com)
3. Create internal test group (TestFlight → Internal Testing → +)
4. Add testers by Apple ID email
5. Testers install the TestFlight app on their iPhone and accept the invite

## Encryption Compliance

Open (2026-11-20): libwimg encrypts sync data itself (XChaCha20-Poly1305, a
standard algorithm), not with Apple's crypto, so "None of the algorithms" (and
`ITSAppUsesNonExemptEncryption: false`) may be wrong. Check Apple's "Complying
with Encryption Export Regulations" before the first App Store submission and
update both. Store listing and answers: `docs/app-store-listing.md`.

## Notes

- Internal testing: up to 100 testers, no Apple review, builds available immediately after processing
- External testing: up to 10,000 testers, first build requires beta review (~24h)
- Privacy manifests: `wimg/PrivacyInfo.xcprivacy`, `wimgWidget/PrivacyInfo.xcprivacy`
  (UserDefaults reasons CA92.1 + 1C8F.1; keep the collected data in step with App Privacy)
- `embed: false` for libwimg.xcframework — it's a static library (.a), linked at compile time
- App icon must be 1024x1024 PNG with no alpha channel
- iPhone only (`TARGETED_DEVICE_FAMILY: "1"`, 2026-11-20): no iPad screenshots or iPad review
