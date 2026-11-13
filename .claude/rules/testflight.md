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

Select "None of the algorithms mentioned above" — the app uses only standard
Apple-provided encryption (HTTPS/TLS).

## Notes

- Internal testing: up to 100 testers, no Apple review, builds available immediately after processing
- External testing: up to 10,000 testers, first build requires beta review (~24h)
- `embed: false` for libwimg.xcframework — it's a static library (.a), linked at compile time
- App icon must be 1024x1024 PNG with no alpha channel
- iPad builds require all 4 orientation entries in Info.plist
