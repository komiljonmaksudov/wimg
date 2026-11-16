# Release Process

## Quick Release

```bash
# 1. Commit changes (conventional format enforced by lefthook)
git add <files> && git commit -m "feat: add changelog page"

# 2. Release + push
./scripts/release.sh patch --push
```

## What `release.sh` Does

1. Reads the current version from `versionName` in `wimg-android/app/build.gradle.kts`
2. Bumps `versionName` there + `MARKETING_VERSION` in `wimg-ios/project.yml`
   (resets `CURRENT_PROJECT_VERSION` to 1)
3. Generates `CHANGELOG.md` entry from commits (filters out `release/chore/ci/build`)
4. Commits as `release: v0.5.18`, tags `v0.5.18`
5. With `--push`: pushes code + tag → CI builds

## Bump Types

```bash
./scripts/release.sh patch          # 0.5.17 → 0.5.18
./scripts/release.sh minor          # 0.5.17 → 0.6.0
./scripts/release.sh major          # 0.5.17 → 1.0.0
./scripts/release.sh 2.0.0          # explicit version
./scripts/release.sh patch --push   # bump + push in one step
```

## Commit Message Format

Enforced by lefthook `commit-msg` hook:

```
type: description
```

| Type       | When                                      |
| ---------- | ----------------------------------------- |
| `feat`     | New feature or functionality              |
| `fix`      | Bug fix                                   |
| `refactor` | Code restructuring, no behavior change    |
| `docs`     | Documentation only                        |
| `style`    | Formatting, no code change                |
| `perf`     | Performance improvement                   |
| `test`     | Adding or fixing tests                    |
| `chore`    | Dependencies, config, tooling             |
| `build`    | Build system changes                      |
| `ci`       | CI/CD pipeline changes                    |

**Filtered from changelog:** `release`, `chore`, `ci`, `build` — these don't appear
in GitHub Releases.

**Tip:** Write commit messages for users, not developers. The message becomes the
changelog entry. `feat: add monthly spending chart` reads better than
`feat: implement BarChart component in AnalysisView`.

## CI Pipeline (`.github/workflows/release.yml`)

Triggered on tag push (`v*`) or manual dispatch:

```
detect-changes     → iOS/Android builds only if the tag touched libwimg/ or the platform dir
check              → zig fmt + zig build test (libwimg, wimg-sync-zig),
                     translation tables match i18n/en.ts (codegen + git diff)
  ↓
build-libwimg-ios  → XCFramework (macos-15)
build-ios          → archive + TestFlight upload (macos-26; skipped without ASC_* secrets)
build-android      → libwimg.so + debug APK (+ signed Play bundle if keystore secrets exist)
build-sync-server  → wimg-sync-zig Linux binary
  ↓
release            → GitHub Release: XCFramework, .so, APK, wimg-sync-linux-x86_64
```

CI never deploys. The landing page and sync server ship from a Mac with
`./scripts/deploy-server.sh [web|sync]`.

## Google Play

- Published from a **personal** developer account. Google requires a closed
  test with ≥ 12 testers opted in for 14 consecutive days before the first
  production release, then a production-access application (review ≤ ~7 days).
- Signed bundle: CI builds `app-release.aab` when the secrets
  `WIMG_KEYSTORE_BASE64`, `WIMG_KEYSTORE_PASSWORD`, `WIMG_KEY_ALIAS`,
  `WIMG_KEY_PASSWORD` exist (upload key; Play App Signing holds the app key).
- Package name `com.wimg.app` is permanent after the first upload.
- **Later (postponed):** an organisation account would skip the tester rule
  but makes the developer a trader with a public business address, needs a
  D-U-N-S number and an Impressum on the website. Revisit if wimg earns money
  or more apps follow; Play supports transferring the app between accounts.
