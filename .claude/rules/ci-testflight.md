# CI TestFlight Upload

GitHub Actions builds and uploads to TestFlight on every `v*` tag push.
Runs on `macos-26` so the binary is linked against the iOS 26 SDK (Apple's
current minimum for App Store Connect uploads).

## One-Time Setup

### 1. Create App Store Connect API Key

1. https://appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API
2. Click `+` to generate a key
3. Name: `wimg-ci`
4. Access: **App Manager** (Admin also works, App Manager is least-privilege)
5. Download the `.p8` file immediately — Apple only shows it once
6. Note the **Key ID** (10-char alphanumeric) and **Issuer ID** (UUID at top of page)

### 2. Add Repository Secrets

GitHub repo → Settings → Secrets and variables → Actions → New repository secret

| Secret Name        | Value                                              |
| ------------------ | -------------------------------------------------- |
| `ASC_KEY_ID`       | 10-char Key ID from step 1                         |
| `ASC_ISSUER_ID`    | UUID Issuer ID from step 1                         |
| `ASC_KEY_CONTENT`  | Full contents of the `.p8` file, including header  |

For `ASC_KEY_CONTENT` paste the whole file as-is:

```
-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGB...
-----END PRIVATE KEY-----
```

### 3. App Store Connect — Bundle IDs Registered

Already done (one-time): `com.wimg.app` (main app) + `com.wimg.app.widget` (extension)
must exist at https://developer.apple.com/account/resources/identifiers with App
Groups capability enabled (`group.com.wimg.app`).

## How It Works

`.github/workflows/release.yml` → `build-libwimg-ios` + `build-ios` jobs:

1. Builds `libwimg.xcframework` via `scripts/build-ios.sh` (macos-15 job, passed on as an artifact)
2. Regenerates `wimg.xcodeproj` via `xcodegen`
3. Writes the API key to `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`
4. Auto-bumps `CURRENT_PROJECT_VERSION` to `$(date +%s)` so every CI run has a
   unique build number (`MARKETING_VERSION` is still controlled by `release.sh`)
5. `xcodebuild archive` with `-allowProvisioningUpdates` + API key flags →
   Xcode auto-creates the Distribution provisioning profile on demand
6. `xcodebuild -exportArchive` with `wimg-ios/ExportOptions.plist`
   (`destination: upload`) → exports IPA and uploads to App Store Connect
   in a single step

Both `wimg` and `wimgWidget` targets are signed automatically because
`project.yml` has `CODE_SIGN_STYLE: Automatic` for both.

## Triggering a Release

```bash
./scripts/release.sh patch --push
```

Pushes a `v*` tag → CI runs `check` → `build-libwimg-ios` → `build-ios` → builds
land on TestFlight in ~10-15 min. iOS jobs are skipped when the tag touched
neither `libwimg/` nor `wimg-ios/`; without the `ASC_*` secrets the upload is
skipped with a warning. Apple processes the build for another
5-15 min before it's selectable in the test group.

## Day-to-Day Flow

```
You:    bump MARKETING_VERSION + git push tag
CI:     archive on macOS 26 + Xcode 26 → upload
Apple:  processes build → email when ready
You:    add build to test group in App Store Connect
```

No local archive. No `.p12` export. No Mac upgrade.

## Troubleshooting

- **`No profiles for 'com.wimg.app' were found`** — API key role too low.
  Make it App Manager (or Admin).
- **`Invalid CFBundleVersion`** — `CURRENT_PROJECT_VERSION` was reused.
  CI auto-bumps via `date +%s`; if running locally bump it manually in
  `project.yml`.
- **`SDK version issue`** — runner not on `macos-26`. Confirm the
  `Show toolchain versions` step prints `Xcode 26.x` / SDK `26.x`.
- **API key not found** — secret `ASC_KEY_CONTENT` was pasted with quotes
  or trailing whitespace; re-paste verbatim from the downloaded `.p8`.

## Manual Override (Emergency)

If CI is broken and you must ship from a Mac, you need Xcode 26 — which
requires macOS 26. Until then, CI is the only path. The old
`.claude/rules/testflight.md` Xcode-archive instructions are stale.
