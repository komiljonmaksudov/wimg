# AGENTS.md

Local-first personal finance app. **`CLAUDE.md` is the canonical, current doc — read it first.**
The detailed pages in `.claude/rules/` go deeper; `phases.md` and `decisions.md` are history.
When a rule file conflicts with CLAUDE.md or the code, trust CLAUDE.md + the code.

## Architecture in one paragraph

`libwimg/` (Zig 0.17.0 + vendored SQLite) **is** the app — all logic, no UI. Two thin shells
render it: `wimg-ios/` (SwiftUI, links `libwimg.a` via C ABI) and `wimg-android/`
(Kotlin/Compose, `libwimg.so` via JNI). `wimg-sync-zig/` is the native Zig sync + MCP server
(self-hosted on Hetzner). `wimg-site/` is the static landing page. There is no web app.
Never put business logic in the shells.

## Gitignored build prerequisites (first build always breaks here)

- `libwimg/vendor/sqlite3.{c,h}` — the SQLite amalgamation is gitignored. No native build
  (iOS, Android, sync server, even `zig build test` in `libwimg`) works without it.
  `make test` (or any native `make` target) fetches it; by hand:
  `curl -fsSL https://www.sqlite.org/2026/sqlite-amalgamation-3520000.zip -o sqlite.zip` then
  unpack `sqlite3.c`/`sqlite3.h` into `libwimg/vendor/`.

## Commands

`make` lists everything. The underlying commands:

| Task | Command | From |
| --- | --- | --- |
| Local sync server :8787 | `./scripts/dev.sh` | repo root |
| libwimg tests | `zig build test` (one test binary per module) | `libwimg/` |
| libwimg format | `zig fmt --check src/` | `libwimg/` |
| Sync server tests | `zig build test` | `wimg-sync-zig/` |
| iOS | `./scripts/build-ios.sh` && `./scripts/gen-xcodeproj.sh` | repo root |
| Android | `./scripts/build-android.sh` && `./gradlew assembleDebug` | repo root / `wimg-android/` |
| i18n codegen | `bun scripts/i18n-codegen.ts` | repo root |
| Landing page + sync server → VPS | `./scripts/deploy-server.sh [web\|sync]` | repo root |

No root `package.json` — bun is only used for scripts.

## i18n — do not translate source text

Source strings stay **German** on disk. `i18n/en.ts` is the single source of truth.
iOS/Android get codegen'd lookup tables — **run `bun scripts/i18n-codegen.ts` after adding or
changing keys** and commit the generated `Translations.swift`/`Translations.kt` (CI fails on a
diff). At call sites use `#L("German")` (iOS, compile-time) / `L("German")` (Android).

## Conventions & gotchas

- **Commits**: conventional commits enforced by lefthook (`type: description`, types
  `feat|fix|refactor|chore|docs|style|perf|test|build|ci`; `release: vX.Y.Z` allowed). The
  message becomes the changelog entry — write for users. Pre-commit runs `zig fmt --check`
  and gitleaks (if installed).
- **Releases**: `./scripts/release.sh <patch|minor|major|X.Y.Z> [--push]` — reads the version
  from `versionName` in `wimg-android/app/build.gradle.kts`, bumps it + `MARKETING_VERSION` in
  `wimg-ios/project.yml`, writes `CHANGELOG.md`, commits, tags, pushes. CI builds iOS,
  Android and the sync server from the tag; iOS/Android only when the tag touched `libwimg/`
  or the platform dir. CI never deploys.
- **iOS**: `wimg-ios/wimg.xcodeproj` is generated from `project.yml` (XcodeGen) — never hand-edit
  the pbxproj; new Swift files are auto-discovered after `./scripts/gen-xcodeproj.sh`.
  `wimg-ios/Frameworks/libwimg.xcframework` is gitignored (built by `build-ios.sh`).
- **Supply chain**: `bunfig.toml` at repo root sets `minimumReleaseAge = 604800` — bun refuses
  packages published <7 days ago. Urgent upgrades: `BUN_INSTALL_MINIMUM_RELEASE_AGE=0 bun install`.
- **Android**: NDK required (`ANDROID_NDK_HOME` or `~/Library/Android/sdk/ndk`); arm64-v8a only.
  `build-android.sh` builds `libwimg.so` + `libwimg-jni.so` with Zig into `jniLibs`; Gradle only
  packages them. CI overrides versionCode via `-PwimgVersionCode`.
- **iOS/Android must stay at parity** — check `.claude/rules/feature-parity.md` before
  shipping a feature to one platform only.
- **Data model**: every row syncs via `updated_at` LWW; sync key IS identity (no accounts).
  E2E encryption client-side — server stores ciphertext only. Pending ("Vorgemerkt")
  transactions are device-only. See `.claude/rules/sync.md` and `wimg-sync-zig/README.md`.

## Testing notes

- `zig build test` in `libwimg/` compiles one test binary per module (see `build.zig`); some
  link the vendored sqlite3.c, others need libc. All must be present for the amalgamation.
- FinTS has auxiliary checkers run with bun (not part of CI): `scripts/test-bank-matrix.ts`
  and `scripts/check-bank-drift.ts`.
- CI (`check` job) runs: zig fmt + `zig build test` (libwimg + sync server), the
  translation-table diff. `make check` runs the same.
