# wimg — Local-First Personal Finance

> libwimg (Zig) · Svelte 5 web · SwiftUI iOS · Kotlin Android (planned)

Last updated: March 2026

---

## Vision

One Zig library — **libwimg** — that IS the app. Every platform (web, iOS) is
a thin shell around it. No logic duplication. Same CSV parser, same
categorization, same SQLite queries, everywhere.

Inspired by libghostty: the library is the product. The UIs are just renderers.

---

## Tech Stack

| Layer           | Choice                                             |
| --------------- | -------------------------------------------------- |
| Shared core     | Zig 0.17.0 + SQLite 3.52.0 (amalgamation)          |
| Web UI          | Svelte 5 + TailwindCSS + LayerChart                |
| Web persistence | OPFS (offline SQLite in browser)                   |
| iOS UI          | SwiftUI + C ABI (libwimg.a)                        |
| Android UI      | Kotlin + Jetpack Compose + JNI (libwimg.so)        |
| Sync            | Self-hosted Zig server (Hetzner) + WebSocket + LWW |
| Categorization  | Keyword rules (~80%) + learned rules + MCP (long tail) |
| Search          | SQL LIKE (planned: FTS5 if needed at scale)        |
| FinTS           | Pure Zig (native-only, iOS + Android)              |
| MCP server      | CF Worker DO + libwimg-compact.wasm                |
| i18n            | Vite plugin (web) + Swift macro `#L` (iOS) + `L()` (Android), single `en.ts` source |

---

## Tooling

- **Formatter:** oxfmt (`.oxfmtrc.json`)
- **Linter:** oxlint (`.oxlintrc.json`) — correctness/error, suspicious/warn, perf/warn
- **Pre-commit:** lefthook (`zig fmt`, `oxfmt`, `oxlint`, commit-msg validation)
- **Commit format:** conventional commits (`feat:`, `fix:`, `refactor:`, etc.) — enforced by lefthook
- **Supply-chain defense:** `bunfig.toml` at repo root sets `minimumReleaseAge = 604800` (7 days). Bun refuses to install any package version published less than a week ago, blocking ~half of historical smash-and-grab attacks at install time. Bypass for urgent upgrades with `BUN_INSTALL_MINIMUM_RELEASE_AGE=0 bun install`.
- **Tests:** `bun test` — format utils + changelog logic
- **Release:** `scripts/release.sh` — bump versions, changelog (filters chore/ci/build), commit, tag, `--push`
- **Build WASM:** `scripts/build-wasm.sh` — two variants (web 209MB + compact 53MB)
- **Build iOS:** `scripts/build-ios.sh` — XCFramework
- **CI:** `.github/workflows/release.yml` — check → build → GitHub release (TestFlight upload commented out — manual via Xcode)
- **Feedback CI:** `.github/workflows/feedback-triage.yml` — Claude Code Action triages user-feedback issues
- **i18n:** `wimg-web/src/lib/translations/en.ts` is the single source of truth. Web: `vite-plugin-i18n.ts` rewrites template/script strings at compile time. iOS: Swift Macro `#L("German")` (SPM package `wimg-ios/plugins/WimgI18n`) + runtime `L(variable)` function — both expand to lookups against the codegen'd `Translations.swift`. Android: top-level `L(...)` Composable in `com.wimg.app.i18n` reading `LocaleState.locale`. One codegen: `scripts/i18n-codegen.ts` writes both runtime tables.

---

## Current Status (March 2026)

Phases 0–4B + 5.0, 5.1, 5.3, 5.7, 5.7b, 5.8, 5.9, 5.10, 5.11, 6.2, 6.3, 6.4, 6.5, 6.6, 6.8, 6.9, 7.0, 7.1, 7.2, 8.0, 8.1 all **done**.

Working: CSV import (Comdirect/TR/Scalable), categorization (keyword rules +
auto-learn), summaries, recurring detection, multi-account, undo/redo,
real-time sync with E2E encryption, MCP server (read tools + categorization +
account writes), data export, monthly snapshots, PWA with offline support,
DevTools panel (5 tabs), Command Palette with SQL LIKE search + search history
+ transaction deep-links, advanced search with date range, amount range slider,
and category filters, in-app changelog (`/changelog`) fetching GitHub Releases
API with localStorage cache, dark mode (light/dark/system with flash
prevention), shared month/year navigation across dashboard/analysis/review via
`dateNav` store, net worth over time chart (SVG area chart in analysis page,
cumulative from snapshots), Sparquote (savings rate) on dashboard hero card,
spending heatmap (GitHub contribution graph style), renewals calendar
(12-month payment forecast with monthly totals, upcoming payments timeline,
next-30-days hero card — tab on recurring page), running balance bar on
transactions list (Comdirect-style: sticky header showing cumulative total of
all transactions from the topmost visible row back through history, web via
IntersectionObserver + SvelteSet, iOS via onAppear/onDisappear tracking).

Embeddings were built (Phase 5.5) then removed (Phase 5.9) — 4,400 lines
deleted. Keyword rules cover ~80% of categorization, MCP + Claude handles
the long tail. Semantic search didn't differentiate well for short queries
against banking descriptions. Simplicity won.

All Svelte stores use class-based reactive pattern (`class Store { #v = $state(...) }`).
No chat UI — Claude Desktop + MCP replaces it.

BottomNav has 3 tabs (Home, Umsätze, Mehr). Analyse moved to More page.
Landing page (`+page.svelte`) is German default. Import and About pages redesigned
with card-based layouts, border styling, and project design tokens.

i18n: one source of truth (`wimg-web/src/lib/translations/en.ts`, ~600 keys),
three platform-specific consumers, no per-platform translation maintenance.

- **Web:** `vite-plugin-i18n.ts` (~200 lines) rewrites Svelte source at
  compile time — `>Gesamtsaldo<` becomes `>{__t$("Gesamtsaldo")}<`. Handles
  template text, attributes, `.name`/`.label` expressions, ternaries, script
  literals, template literals, `.svelte.ts` files.
- **iOS:** Swift Macro `#L("German")` (SPM package at
  `wimg-ios/plugins/WimgI18n`) expands at compile time to `__t("German")`.
  Interpolation extracts a template: `#L("\(count) Transaktionen")` →
  `__t("%@ Transaktionen", count)`. For runtime strings (e.g.
  `category.name`), use the plain function `L(variable)` — same lookup.
- **Android:** Top-level Composable `L(key)` in `com.wimg.app.i18n` reads
  `LocaleState.locale`. Single call shape everywhere: `Text(L("German"))`.

Codegen: `scripts/i18n-codegen.ts` writes both runtime tables
(`wimg-ios/plugins/WimgI18n/Sources/WimgI18n/Translations.swift` +
`wimg-android/app/src/main/java/com/wimg/app/i18n/Translations.kt`) from
`en.ts`. Reactive locale switching via `wimg_locale` UserDefaults (iOS) /
`LocaleState` (Android). For dates, `DateFormatter` with locale from
`wimg_locale` — never hardcode German month/day names.

Migration notes: `TText`, `.xcstrings`, `String(localized:)`, and the
hand-maintained Android `TranslationMap` were all removed during this
refactor (May 2026). Source stays vanilla German on disk — `Text("X")` or
`Text(#L("X"))` (iOS) / `Text(L("X"))` (Android) at call sites only.

Conventional commits enforced by lefthook `commit-msg` hook.

LayerChart removed — all charts are pure SVG (DonutChart, NetWorthChart,
SpendingHeatmap). Changelog page shows commit type badges
(feat/fix/refactor/perf) with grid layout. About page has 22 FAQ entries
with hash-anchor deep-links from Command Palette (`afterNavigate` +
`noScroll` goto for reliable scrolling past Drawer body lock).
UpdateBanner changelog fallback for unreleased versions.

Drawer component (renamed from BottomSheet) with Base UI-inspired stacking:
global `drawerStore` tracks open drawers, portal to `document.body`, dynamic
z-index from stack depth, CSS-driven indent when nested (custom properties
`--indent-scale`/`--indent-y`), input isolation, dim overlay, data attributes
(`data-open`, `data-swiping`, `data-nested-drawer-open`). `DrawerIndent`
wraps page content for scale-down effect when any drawer opens. Sonner-style
stacked toasts (multiple simultaneous, hover-to-pause, swipe-to-dismiss).

Hosting (Aug 2026): wimg no longer runs on Cloudflare. `wimg-sync.mili-my.name`
is the native Zig server (`wimg-sync-zig/`) on a Hetzner VPS behind Caddy, and
`wimg.mili-my.name` is the static SPA (`adapter-static`) served from
`/var/www/wimg` on the same box. See `.claude/rules/sync.md` and `infra/`.
The old Cloudflare Worker in `wimg-sync/` is kept as a rollback path only.
Everything else on the `mili-my.name` zone still uses Cloudflare DNS.

There is no in-app feedback system. An earlier `POST /feedback` endpoint on
wimg-sync is gone — no route in any server and no client calls it. The
`feedback-triage.yml` workflow still triages manually-filed GitHub issues.

Simplification pass (2026-05-14): tax, goals, and debts UI surface removed on
all three platforms. Tax was purely derived (no schema/C ABI) and is fully
gone. Goals + Debts kept their Zig C ABI exports and SQLite tables (`debts`,
`savings_goals`) for cheap resurrection, but Swift/TS bindings, MCP tools,
feature flags, navigation entries, settings toggles, and About FAQ entries
are deleted. Bun test count dropped (tax tests gone).

iOS dark mode support (ThemeManager with light/dark/system, adaptive colors
in WimgTheme, settings picker). Onboarding has 4 cards: privacy, import,
recurring detection, sync. SearchView has nav links to remaining features
(Analyse, Wiederkehrend, Rückblick, Bankverbindung, Import, Einstellungen).

FinTS 3.0 protocol engine (pure Zig, ~2500 lines): anonymous init, authenticated
dialog (PIN/TAN), HKKAZ v5/v6/v7 statement fetch (version negotiated from BPD),
MT940 + CAMT parsing, photoTAN challenge extraction, decoupled TAN polling
(HKTAN process-S with BPD-derived timings), TAN mechanism auto-selection from
`3920`, HKTAB TAN medium fetch + selection (for banks requiring
`description_required=2`), touchdown pagination with structured `3040` extraction.
HTTP transport via C ABI callback (URLSession on iOS). Tested with Comdirect
(BLZ 20041177). Top-bank matrix script validates 8 major banks (anon init probe).
Bank catalog drift checker compares official CSV against `banks.zig` (1,745 entries).
Key protocol details: bare envelope (no HNVSK/HNVSD) for standard banks,
HNVSK/HNVSD envelope for Deutsche Bank/Postbank/norisbank family,
HKTAN v2-v7, contiguous segment numbering, YYYYMMDD dates, DEG colons not
escaped. Static buffers for Base64 encode/decode (prevent stack overflow on
iOS GCD threads). Bank-family detection from URL (`BankFamily` enum in
`banks.zig`) auto-selects envelope style. Anonymous customer_id uses
`9999999999` per FinTS spec (not `0`).

Contextual onboarding (Phase 7.1): empty state CTAs on all screens
(Goals, Debts, Review, Tax, Transactions — iOS + web), post-import next
steps (dashboard/transactions nav buttons), coachmarks system (3 first-visit
tooltips: donut chart, transaction list, category breakdown). iOS
SpendingHeatmap tap-to-select with inline amount label. CoachmarkManager
(iOS, UserDefaults) + coachmarks.svelte.ts (web, localStorage).

FinTS Quick Refresh (Phase 6.9 v1, done): opt-in PIN storage in Keychain
(`fints_pin`, `kSecAttrAccessibleAfterFirstUnlock`), "PIN merken" toggle on
credentials screen, TAN medium name persisted (`fints_tan_medium`).
Quick refresh card ("Schnellabfrage") with one-tap "Aktualisieren" when
saved credentials exist — auto-connects, auto-restores TAN medium, skips
to TAN challenge if needed, silent fetch (last 90 days) for no-TAN paths.
On auth failure clears stored PIN and falls back to manual form.
v2 (deferred): `BGAppRefreshTask` for background fetch.

Phase 8.0 (Android, done — full parity with iOS): Kotlin + Jetpack Compose
shell over libwimg.so. JNI C shim (`wimg_jni.c`, 44 functions) compiled by
NDK CMake. 15 screens at full feature parity: Dashboard (hero + Sparquote
ring + categories), Transactions (list + category editor + advanced filter
sheet with amount/category/search), Analysis (category breakdown + net worth
+ spending heatmap), Debts (CRUD + progress), Goals (icon picker +
contribute), Recurring (grouped by interval + renewals calendar tab with
12-month forecast), Review (monthly savings/deficit), Tax (Pendlerpauschale
+ Homeoffice), Import (file picker), Search (quick actions: nav links,
auto-categorize, export, undo/redo), Settings (theme/language picker,
feature toggles, sync enable/link, data export/reset with confirmation),
About (19 FAQ with expandable answers, privacy, GitHub), FinTS (bank
search, credentials, TAN, statement fetch, 2MB stack thread, Quick Refresh
with PIN storage), Feedback (POST to wimg-sync), Onboarding (4-card
carousel), More (grid). Sync via OkHttp WebSocket + HTTP push/pull + E2E
encryption. Undo snackbar wired globally. Coachmarks (2 first-visit
tooltips). Account switcher in top bar. i18n via `L()` Composable
(`com.wimg.app.i18n`) reading `LocaleState.locale`; 546 keys generated from
`en.ts`. Update checker with changelog
from GitHub Releases API. Demo data service. Material 3 theme with
`wimgCard()`/`wimgHero()` modifiers, custom Typography, subtle shadows.
4-tab bottom nav (Search, Home, Umsätze, Mehr). Sideload APK distribution.
CI builds debug APK + attaches to GitHub Release.

Phase 8.1 (Home Screen Widgets, done): iOS WidgetKit + Android Glance.
iOS: single `WimgWidget` declaring all four families (`systemSmall`,
`systemMedium`, `systemLarge`, `accessoryRectangular`) so users get
size variants in one gallery entry; `WimgWidgetEntryView` switches by
`@Environment(\.widgetFamily)`. Small (2×2): available + Sparquote.
Medium (4×2): available + Sparquote + next recurring. Large (4×4):
header + Einnahmen/Ausgaben + 5 most recent transactions. Lock screen
rectangular accessory. All widgets use
`frame(maxWidth: .infinity, maxHeight: .infinity)` to fill the
container — `containerBackground` alone doesn't size content on
iOS 17+. Data sharing via App Groups (`group.com.wimg.app`).
Android: Glance app widgets at parity (Small/Medium/Large), data
shared via SharedPreferences (`wimg_widget`). Glance 1.1 API requires
single-arg `ColorProvider(color)` (no day/night named args), no
`GlanceTheme` / `ColorProviders` — direct `background(Color)`.
Each receiver registered separately in AndroidManifest with its own
`appwidget-provider` XML (resizable, `targetCellWidth/Height`).
`WidgetDataWriter` writes summary + recurring + recent transactions
JSON, calls `updateAll(context)` on all three Glance widgets after
every dashboard reload. iOS uses `WidgetCenter.shared.reloadAllTimelines()`.

Phase 6.9 v2 (background FinTS refresh + notifications) is **done on iOS and
Android**. iOS: `BackgroundRefresh.swift` — `BGAppRefreshTask` registered in
`App.init()`, 24h floor, silent connect + 14-day fetch with the Keychain PIN,
local notification via `UNUserNotificationCenter`. Android:
`services/BackgroundRefresh.kt` — WorkManager `PeriodicWorkRequest` (1 day, 6h
flex, network + battery-not-low constraints) running the same flow against the
SharedPreferences PIN, notification via `NotificationCompat`.

Both dedupe "TAN erforderlich" inside a 24h cooldown, skip scheduling entirely
when no PIN is stored, cancel on auth failure, and stay silent when nothing was
imported. Permission is requested in context after a successful Schnellabfrage,
never at launch. Opt-out toggle in Settings (`wimg_bg_refresh_enabled`).
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
One Zig library (libwimg) IS the app. Every platform (web, iOS) is a thin
shell that renders what the library returns. No logic duplication. Same CSV
parser, same categorization, same queries, everywhere. Inspired by libghostty.

### Don't fight the platform
C ABI for cross-platform. WASM for web, static lib for iOS. Use what each
platform gives you (OPFS on web, files on iOS, SwiftUI vs Svelte). Don't
abstract away platform differences — embrace them at the shell level.

### Earned complexity
Start simple. Add complexity only when the simple solution demonstrably fails.
LWW sync instead of CRDTs (one person, two devices). SQL LIKE before FTS5.
Keyword rules before embeddings. Every abstraction must justify its existence.

### Security by default
E2E encryption for sync — key derived from sync key, server sees only
ciphertext. PII stripping for MCP responses. No accounts, no passwords —
sync key IS the identity.

### Zero overhead for dev features
DevTools, feature flags, debug logging — all tree-shaken in production.
`devtoolsEnabled` boolean = zero cost when off. No runtime overhead for
things users never see.

---

## Detailed Documentation

Split into `.claude/rules/` for context efficiency:

- `architecture.md` — full architecture diagrams, data flow, tech stack details
- `schema.md` — complete SQLite schema (all tables)
- `c-abi.md` — all C ABI function signatures + WASM memory budget
- `phases.md` — all phase details (completed + future)
- `sync.md` — sync system, E2E encryption, MCP server, API
- `devtools.md` — DevTools panel (5 tabs, activation, architecture)
- `feature-flags.md` — feature flag system (web + iOS)
- `feature-parity.md` — iOS vs web parity table
- `file-structure.md` — complete file tree
- `decisions.md` — decision log (all architectural choices)
- `release.md` — release process, commit format, CI pipeline
- `banking-aggregators.md` — PSD2/PSD3 research, aggregator comparison, AISP licensing
- `testflight.md` — TestFlight setup, upload process, versioning
- `ci-testflight.md` — GitHub Actions TestFlight upload (Apple secrets, signing, troubleshooting)
- `fints.md` — FinTS 3.0 technical deep dive (wire format, TAN flow, paging, MT940)
