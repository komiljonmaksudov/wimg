# AGENTS.md

Local-first personal finance app. **`CLAUDE.md` is the canonical, current doc — read it first.**
The detailed pages in `.claude/rules/` are the deep-dive archive but several are stale
(embeddings/gguf, debts/goals/tax UI, LayerChart, CF Durable Objects as primary sync).
When a rule file conflicts with CLAUDE.md or the code, trust CLAUDE.md + the code.

## Architecture in one paragraph

`libwimg/` (Zig 0.16.0 + vendored SQLite) **is** the app — all logic, no UI. Three thin shells
render it: `wimg-web/` (Svelte 5, loads `libwimg.wasm` via OPFS), `wimg-ios/` (SwiftUI, links
`libwimg.a` via C ABI), `wimg-android/` (Kotlin/Compose, `libwimg.so` via JNI). `wimg-sync-zig/`
is the native Zig sync server (production, self-hosted on Hetzner). `wimg-sync/` is the old
Cloudflare Worker — **rollback path only, never deploy it**. Never put business logic in the shells.

## Gitignored build prerequisites (first build always breaks here)

- `libwimg/vendor/sqlite3.{c,h}` — the SQLite amalgamation is gitignored. No native build
  (iOS, Android, sync server, even `zig build test` in `libwimg`) works without it.
  Download exactly what CI does (`release.yml`):
  `curl -fsSL https://www.sqlite.org/2026/sqlite-amalgamation-3520000.zip -o sqlite.zip` then
  unpack `sqlite3.c`/`sqlite3.h` into `libwimg/vendor/`.
- `wimg-web/static/libwimg.wasm` — built by `./scripts/build-wasm.sh`; the web app fetches
  `/libwimg.wasm` at runtime, so run this **before** `bun run dev` or `bun run build`.
  It builds both variants (web + compact for the MCP server) and installs both copies.

## Commands

| Task | Command | From |
| --- | --- | --- |
| Full-stack dev (sync :8787 + web :5173) | `./scripts/dev.sh` | repo root |
| Same but native Zig sync server | `WIMG_NATIVE_SYNC=1 ./scripts/dev.sh` | repo root |
| Web dev alone | `bun run dev` | `wimg-web/` |
| Web typecheck | `bun run check` (svelte-check) | `wimg-web/` |
| Web lint / format | `bunx oxlint` / `bunx oxfmt --check` | `wimg-web/` |
| Web tests | `bun test` (only `src/lib/format.test.ts`) | `wimg-web/` |
| libwimg tests | `zig build test` (one test binary per module) | `libwimg/` |
| libwimg format | `zig fmt --check src/` | `libwimg/` |
| Sync server tests | `zig build test` | `wimg-sync-zig/` |
| WASM (web + compact) | `./scripts/build-wasm.sh` | repo root |
| iOS | `./scripts/build-ios.sh` && `./scripts/gen-xcodeproj.sh` | repo root |
| Android | `./scripts/build-android.sh` && `./gradlew assembleDebug` | repo root / `wimg-android/` |
| i18n codegen | `bun scripts/i18n-codegen.ts` | repo root |

No root `package.json` — dependencies live only in `wimg-web/` and `wimg-sync/`.

## i18n — do not translate source text

Source strings stay **German** on disk. `wimg-web/src/lib/translations/en.ts` is the single
source of truth (~600 keys). Web: `vite-plugin-i18n.ts` rewrites German literals to `__t$()`
at compile time (so it works in `.svelte` files and `.svelte.ts` stores automatically).
iOS/Android get codegen'd lookup tables — **run `bun scripts/i18n-codegen.ts` after adding or
changing keys** and commit the generated `Translations.swift`/`Translations.kt`. At call sites
use `#L("German")` (iOS, compile-time) / `L("German")` (Android); `__t$()` is web-internal.

## Conventions & gotchas

- **Commits**: conventional commits enforced by lefthook (`type: description`, types
  `feat|fix|refactor|chore|docs|style|perf|test|build|ci`; `release: vX.Y.Z` allowed). The
  message becomes the changelog entry — write for users. Pre-commit runs `zig fmt --check`,
  `oxfmt --check`, `oxlint`.
- **Releases**: `./scripts/release.sh <patch|minor|major|X.Y.Z> [--push]` — bumps version in
  `wimg-web/package.json` + `wimg-ios/project.yml`, writes `CHANGELOG.md`, commits, tags, pushes.
  CI builds web + iOS + Android + sync server from the tag. iOS/Android native builds only run
  when the tag touched `libwimg/` or the platform dir.
- **iOS**: `wimg-ios/wimg.xcodeproj` is generated from `project.yml` (XcodeGen) — never hand-edit
  the pbxproj; new Swift files are auto-discovered after `./scripts/gen-xcodeproj.sh`.
  `wimg-ios/Frameworks/libwimg.xcframework` is gitignored (built by `build-ios.sh`).
- **Supply chain**: `bunfig.toml` at repo root sets `minimumReleaseAge = 604800` — bun refuses
  packages published <7 days ago. Urgent upgrades: `BUN_INSTALL_MINIMUM_RELEASE_AGE=0 bun install`.
- **Svelte stores**: all use the class-based reactive pattern (`class Store { #v = $state(...) }`),
  not writable singleton `$state`. Charts are pure SVG — LayerChart was removed.
- **Web OPFS** needs COOP/COEP headers (already set in `vite.config.ts`); don't remove them.
- **Web sync URL**: `config.ts` auto-switches to `http://<host>:8787` on localhost/LAN, else the
  prod server. No manual config needed.
- **Android**: NDK required (`ANDROID_NDK_HOME` or `~/Library/Android/sdk/ndk`); arm64-v8a only.
  `versionName` lives in `wimg-android/app/build.gradle.kts` (CI overrides versionCode via
  `-PwimgVersionCode`).
- **Web/iOS/Android must stay at parity** — check `.claude/rules/feature-parity.md` before
  shipping a feature to one platform only.
- **Data model**: every row syncs via `updated_at` LWW; sync key IS identity (no accounts).
  E2E encryption client-side — server stores ciphertext only. See `.claude/rules/sync.md` and
  `wimg-sync-zig/README.md` (wire-compatible, read that one for the current server).

## Testing notes

- `zig build test` in `libwimg/` compiles one test binary per module (see `build.zig`); some
  link the vendored sqlite3.c, others need libc. All must be present for the amalgamation.
- FinTS has auxiliary checkers run with bun (not part of CI): `scripts/test-bank-matrix.ts`
  and `scripts/check-bank-drift.ts`.
- CI (`check` job) runs the full gate: zig fmt, `zig build test` (libwimg + sync server),
  oxfmt, oxlint, `bun test`, svelte-check, `tsc --noEmit` (wimg-sync). Run these locally.
