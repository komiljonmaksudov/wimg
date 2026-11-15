# wimg — Local-First Personal Finance

> libwimg (Zig) · SwiftUI iOS · Kotlin Android

Last updated: November 2026

---

## Vision

One Zig library — **libwimg** — that IS the app. Every platform (iOS, Android)
is a thin shell around it. No logic duplication. Same CSV parser, same
categorization, same SQLite queries, everywhere.

Inspired by libghostty: the library is the product. The UIs are just renderers.

---

## Tech Stack

| Layer           | Choice                                             |
| --------------- | -------------------------------------------------- |
| Shared core     | Zig 0.17.0 + SQLite 3.52.0 (amalgamation)          |
| iOS UI          | SwiftUI + C ABI (libwimg.a)                        |
| Android UI      | Kotlin + Jetpack Compose + JNI (libwimg.so)        |
| Sync            | Self-hosted Zig server (Hetzner) + WebSocket + LWW |
| Categorization  | Keyword rules (~80%) + learned rules + MCP (long tail) |
| Search          | SQL LIKE                                           |
| FinTS           | Pure Zig (native-only, iOS + Android)              |
| MCP server      | `POST /mcp` on the Zig sync server, libwimg linked natively |
| i18n            | Swift macro `#L` (iOS) + `L()` (Android), single `i18n/en.ts` source |
| Website         | Static landing page (`wimg-site/`)                 |

Licence: MIT (`LICENSE`).

---

## Tooling

- **Pre-commit:** lefthook (`zig fmt --check`, gitleaks if installed, commit-msg validation)
- **Commit format:** conventional commits (`feat:`, `fix:`, `refactor:`, etc.) — enforced by lefthook
- **Supply-chain defense:** `bunfig.toml` at repo root sets `minimumReleaseAge = 604800` (7 days). Bun refuses to install any package version published less than a week ago. Bypass for urgent upgrades with `BUN_INSTALL_MINIMUM_RELEASE_AGE=0 bun install`.
- **Everyday commands:** `make` lists them (`test`, `check`, `ios`, `android`, `i18n`, `deploy*`, `release-*`)
- **Tests:** `zig build test` in `libwimg/` and `wimg-sync-zig/`
- **Release:** `scripts/release.sh` — version from Android `versionName`, bumps it + iOS `MARKETING_VERSION`, changelog (filters chore/ci/build), commit, tag, `--push`
- **Build WASM:** `scripts/build-wasm.sh` — compact build for the rollback Worker only
- **Build iOS / Android:** `scripts/build-ios.sh` (XCFramework) / `scripts/build-android.sh` (libwimg.so + libwimg-jni.so)
- **CI:** `.github/workflows/release.yml` — check (incl. translation-table diff) → wasm, iOS (TestFlight), Android, sync server → GitHub release. CI never deploys; `./scripts/deploy-server.sh` ships site + sync server from a Mac.
- **i18n:** `i18n/en.ts` is the single source of truth. `scripts/i18n-codegen.ts` writes `wimg-ios/plugins/WimgI18n/Sources/WimgI18n/Translations.swift` and `wimg-android/app/src/main/java/com/wimg/app/i18n/Translations.kt`; CI fails if they are out of date.

---

## Current Status (November 2026)

Phases 0–4B + 5.0, 5.1, 5.3, 5.8, 5.9, 5.10, 6.2, 6.5–6.9, 7.0, 7.1, 8.0, 8.1
**done**. The web app (and with it 5.7, 5.7b, 5.11 and web i18n) was removed in
Nov 2026.

Working: CSV import (Comdirect/TR/Scalable), FinTS fetch, categorization
(keyword rules + auto-learn), summaries, recurring detection, multi-account,
undo/redo, real-time sync with E2E encryption, MCP server, data export,
monthly snapshots, Sparquote (savings rate), pending ("Vorgemerkt")
transactions on Android, app lock, home screen widgets, background bank
refresh. Platform differences: `.claude/rules/feature-parity.md`.

Embeddings were built (Phase 5.5) then removed (Phase 5.9) — 4,400 lines
deleted. Keyword rules cover ~80% of categorization, MCP + Claude handles
the long tail. Semantic search didn't differentiate well for short queries
against banking descriptions. Simplicity won. No chat UI — Claude Desktop +
MCP replaces it.

i18n: one source of truth (`i18n/en.ts`), two platform consumers, no
per-platform translation maintenance.

- **iOS:** Swift Macro `#L("German")` (SPM package at
  `wimg-ios/plugins/WimgI18n`) expands at compile time to `__t("German")`.
  Interpolation extracts a template: `#L("\(count) Transaktionen")` →
  `__t("%@ Transaktionen", count)`. For runtime strings (e.g.
  `category.name`), use the plain function `L(variable)` — same lookup.
- **Android:** Top-level Composable `L(key)` in `com.wimg.app.i18n` reads
  `LocaleState.locale`. Single call shape everywhere: `Text(L("German"))`.

Run `bun scripts/i18n-codegen.ts` after changing `en.ts` and commit both
generated tables. Reactive locale switching via `wimg_locale` UserDefaults
(iOS) / `LocaleState` (Android). For dates, `DateFormatter` with locale from
`wimg_locale` — never hardcode German month/day names. Source stays vanilla
German on disk — `Text("X")` or `Text(#L("X"))` (iOS) / `Text(L("X"))`
(Android) at call sites only.

Hosting (Aug 2026): wimg no longer runs on Cloudflare. `wimg-sync.komiljonmaksudov.com`
is the native Zig server (`wimg-sync-zig/`, sync + MCP) on a Hetzner VPS
behind Caddy. See `.claude/rules/sync.md` and `infra/`. The old Cloudflare
Worker in `wimg-sync/` is kept as a rollback path only.

Domain move (Nov 2026): both names moved from `mili-my.name` to
`komiljonmaksudov.com` (DNS at Namecheap, A records → 91.98.69.226). The
old `wimg.mili-my.name` / `wimg-sync.mili-my.name` names were cut over at
once, not served in parallel: app builds from before the move can't sync
until they're updated.

Landing page (Nov 2026): the web app is gone (`wimg-web/` deleted).
`wimg.komiljonmaksudov.com` is a static landing page built from `wimg-site/`
(`python3 wimg-site/build.py` → `wimg-site/public/`, deployed by
`./scripts/deploy-server.sh web`). `src/index.html` + `src/site.js` are the
page from Brief 18 (direction "Schreibtisch": a desk of demo papers, app
windows, the squirrel that follows the cursor and changes mood on tap); the
script is a file because the CSP allows no inline scripts.
**Demo data only**: every amount, merchant and bank in those screens is
invented (Musterbank, Grünstrom AG, Muster GmbH). Re-exports from the canvas
carry the owner's real data and must be replaced before they land in the
repo. The site keeps no access logs (`infra/wimg-web.caddy` has no `log`
block) and loads nothing from third parties; `datenschutz.html` says so.

There is no feedback system. An earlier `POST /feedback` endpoint on
wimg-sync is gone — no route in any server and no client calls it.

Simplification pass (2026-05-14): tax, goals, and debts UI surface removed on
all platforms. Tax was purely derived (no schema/C ABI) and is fully gone.
Goals + Debts kept their Zig C ABI exports and SQLite tables (`debts`,
`savings_goals`) for cheap resurrection; bindings, MCP tools, navigation
entries and FAQ entries are deleted.

FinTS 3.0 protocol engine (pure Zig, ~2500 lines): anonymous init, authenticated
dialog (PIN/TAN), HKKAZ v5/v6/v7 statement fetch (version negotiated from BPD),
MT940 + CAMT parsing, photoTAN challenge extraction, decoupled TAN polling
(HKTAN process-S with BPD-derived timings), TAN mechanism auto-selection from
`3920`, HKTAB TAN medium fetch + selection (for banks requiring
`description_required=2`), touchdown pagination with structured `3040` extraction.
Booked and pending ("Vorgemerkt") parts of the answer are read apart; pending
entries go to `pending_transactions` (device-only, replaced every fetch, never
synced or summed). HTTP transport via C ABI callback (URLSession on iOS, OkHttp
on Android). Tested with Comdirect (BLZ 20041177). Top-bank matrix script
validates 8 major banks (anon init probe). Bank catalog drift checker compares
official CSV against `banks.zig`. Key protocol details: bare envelope (no
HNVSK/HNVSD) for standard banks, HNVSK/HNVSD envelope for Deutsche
Bank/Postbank/norisbank family, HKTAN v2-v7, contiguous segment numbering,
YYYYMMDD dates, DEG colons not escaped. Static buffers for Base64
encode/decode (prevent stack overflow on iOS GCD threads). Bank-family
detection from URL (`BankFamily` enum in `banks.zig`) auto-selects envelope
style. Anonymous customer_id uses `9999999999` per FinTS spec (not `0`).
iOS builds the FinTS request JSON with `JSONEncoder` (PINs with quotes are safe).

FinTS Quick Refresh (Phase 6.9 v1): opt-in PIN storage — iOS Keychain
(`fints_pin`, `kSecAttrAccessibleAfterFirstUnlock`), Android encrypted with an
AES-256-GCM Android Keystore key (`services/PinStore.kt`; `allowBackup=false`).
"PIN merken" toggle on the credentials screen, TAN medium name persisted.
Quick refresh card ("Schnellabfrage") with one-tap "Aktualisieren" when
saved credentials exist — auto-connects, auto-restores TAN medium, skips
to TAN challenge if needed, silent fetch for no-TAN paths. On auth failure
clears stored PIN and falls back to manual form.

Android (Phase 8.0): Kotlin + Jetpack Compose shell over libwimg.so. JNI C
shim (`app/src/main/cpp/wimg_jni.c`) compiled with Zig by
`build-android.sh` into `libwimg-jni.so`; Gradle only packages the two `.so`
files. Navigation (`ui/navigation/WimgNavigation.kt`): one floating bar with a
places menu — Übersicht, Umsätze, Wiederkehrend, Rückblick, Bankverbindung,
Import, Einstellungen, Über wimg — plus Search, transaction and recurring
detail pages. Pending transactions shown greyed at the top of Umsätze and on
Home. Über wimg has news (update checker against GitHub Releases), FAQ,
privacy, licences. App lock via `BiometricLock`. Sync via OkHttp WebSocket +
HTTP push/pull + E2E encryption. Demo data service. Sideload APK + signed
Play bundle from CI. Analyse, More, Debts, Goals, Tax and Feedback screens
and `TText` are gone.

iOS: `TabView` with Suche, Home, Umsätze, Mehr; Mehr links to Analyse (net
worth + spending heatmap), Wiederkehrend, Import, Bankverbindung, Rückblick,
Einstellungen, Über. Dark mode via ThemeManager (light/dark/system).

Phase 8.1 (Home Screen Widgets): iOS WidgetKit + Android Glance.
iOS: single `WimgWidget` declaring all four families (`systemSmall`,
`systemMedium`, `systemLarge`, `accessoryRectangular`); the entry view
switches by `@Environment(\.widgetFamily)`. All widgets use
`frame(maxWidth: .infinity, maxHeight: .infinity)` to fill the
container — `containerBackground` alone doesn't size content on
iOS 17+. Data sharing via App Groups (`group.com.wimg.app`).
Android (board 13, `widget/Widgets.kt`): Monat (4×2, dark: Verfügbar,
category bar, Ausgaben, Ausgaben/Tag, Stand), Fixkosten offen (2×2) and Heute
(2×2). `WidgetDataWriter` computes everything and stores one JSON in
SharedPreferences (`wimg_widget`); widgets never call libwimg. "Beträge in
Widgets ausblenden" shows `•••• €`. The category bar is a bitmap (Glance has
no proportional weights). Glance 1.1 API requires single-arg
`ColorProvider(color)` (no day/night named args), no `GlanceTheme` /
`ColorProviders` — direct `background(Color)`. Each receiver registered
separately in AndroidManifest with its own `appwidget-provider` XML.

Phase 6.9 v2 (background FinTS refresh + notifications) is **done on iOS and
Android**. iOS: `BackgroundRefresh.swift` — `BGAppRefreshTask` registered in
`App.init()`, 24h floor, silent connect + 14-day fetch with the Keychain PIN,
local notification via `UNUserNotificationCenter`. Android:
`services/BackgroundRefresh.kt` — WorkManager `PeriodicWorkRequest` (1 day,
network + battery-not-low constraints) running the same flow with the
Keystore-encrypted PIN, notification via `NotificationCompat`.

Both dedupe "TAN erforderlich" inside a 24h cooldown, skip scheduling entirely
when no PIN is stored, cancel on auth failure, and stay silent when nothing was
imported. Permission is requested in context after a successful Schnellabfrage,
never at launch. Opt-out toggle in Settings (`wimg_bg_refresh_enabled`).
Android notifications follow board 13: title + one line, "Jetzt abrufen" on
the TAN one, and a month-end notice ("Dein Oktober ist abgeschlossen", daily
`MonthEndWorker`, first 5 days of a month, once) that opens Rückblick on that
month. Notifications and widgets open pages via the `wimg_route` intent extra.
Platform difference: iOS lets the system learn a cadence; WorkManager has no
equivalent, so Android asks for daily and Doze may defer it.

Price-change alerts on recurring payments are still unbuilt — the original
Phase 6.9 v2 scope included them. Absorbs the deferred Phase 5.2
(Notifications) and replaces Phase 7.3 (Vertragsmanagement, dropped).

---

## Principles

### Simplicity above all
Less code is better code. If a feature needs 2000 lines of infra for marginal
gain, it's not worth it. Prefer boring, proven solutions (SQL LIKE, keyword
rules) over clever ones (ML models, vector search). Every line of code is a
liability.

### 80/20 — Pareto Principle
Solve 80% of the problem with 20% of the effort. Keyword rules categorize ~80%
of transactions — that's good enough. MCP + Claude handles the long tail
on-demand. Don't build complex systems to automate the last 20%.

### Local-first, offline always
All data lives in SQLite. The app works fully offline with zero server
dependency. Network is an enhancement (sync), not a requirement. No loading
spinners for core functionality.

### Library is the product
One Zig library (libwimg) IS the app. Every platform (iOS, Android) is a thin
shell that renders what the library returns. No logic duplication. Same CSV
parser, same categorization, same queries, everywhere. Inspired by libghostty.

### Don't fight the platform
C ABI for cross-platform: static lib for iOS, shared lib + JNI for Android.
Use what each platform gives you (Keychain vs Keystore, BGAppRefreshTask vs
WorkManager, SwiftUI vs Compose). Don't abstract away platform differences —
embrace them at the shell level.

### Earned complexity
Start simple. Add complexity only when the simple solution demonstrably fails.
LWW sync instead of CRDTs (one person, two devices). SQL LIKE before FTS5.
Keyword rules before embeddings. Every abstraction must justify its existence.

### Security by default
E2E encryption for sync — key derived from sync key, server sees only
ciphertext. PII stripping for MCP responses. No accounts, no passwords —
sync key IS the identity.

---

## Detailed Documentation

Split into `.claude/rules/` for context efficiency:

- `architecture.md` — architecture overview, data flow
- `schema.md` — complete SQLite schema (all tables)
- `c-abi.md` — all C ABI function signatures + compact WASM budget
- `phases.md` — all phase details (completed + future)
- `sync.md` — sync server, E2E encryption, MCP server, API
- `feature-parity.md` — iOS vs Android parity table
- `file-structure.md` — file tree
- `decisions.md` — decision log (all architectural choices)
- `release.md` — release process, commit format, CI pipeline
- `banking-aggregators.md` — PSD2/PSD3 research, aggregator comparison, AISP licensing
- `testflight.md` — TestFlight setup, upload process, versioning
- `ci-testflight.md` — GitHub Actions TestFlight upload (Apple secrets, signing, troubleshooting)
- `fints.md` — FinTS 3.0 technical deep dive (wire format, TAN flow, paging, MT940)
- `android-performance.md` — judging smoothness (bench build), measuring frames, what was slow
