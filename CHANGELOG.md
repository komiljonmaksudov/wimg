# Changelog

## v0.9.14 (2026-11-20)

- fix(ios): a bank error after a good sign-in says Abruf fehlgeschlagen with the bank's reason; the stored PIN is only forgotten when the bank refuses the login, as on Android
- fix: a first bank fetch over months no longer fails (CAMT answers up to several MB, transaction list off the FinTS thread's stack); iOS sends a TAN only once at a time
- fix: the squirrel's bubble stays on screen (narrow phones, long lines); iOS Umsätze sum follows the scroll as on Android
- feat(ios): App-Sperre as on Android: lock after (immediately, 1, 5 or 15 min) and hide amounts in the app switcher and in screen recordings
- feat(ios): Einstellungen as on Android: wimg Sync and App-Sperre on their own pages, Mitteilungen next to Konten; transaction details as flat rows
- fix(android): Fertig in the account panel on Übersicht no longer flashes the month panel while it closes
- feat(ios): Wiederkehrend, Rückblick, Import and Über wimg as on Android; demo data as on Android (Gehaltsmonat, cash, nothing after today); the squirrel catches price rises; new app icon on the lock and welcome screens
- feat(ios): Übersicht and Umsätze as on Android: squirrel in the day ring, last fetch time, one colour bar for the categories, category icons, the latest day's bookings, flat rows
- feat(ios): FAQ as on Android (grouped, searchable); the pinned Umsätze bar follows the scroll, smaller, with a soft edge
- docs: CAMT first tested on the phone
- fix(ios): Umsätze keeps the sum and its buttons at the top while scrolling; rows no longer run under the status bar; Suche tiles no longer break words
- feat: bank fetches ask for CAMT first wherever the bank offers it, MT940 only as the fallback (MT940 is being retired); Android names MT940 on a bank that needs it
- docs: field note on the unescaped PIN and the UTF-8 TAN media names
- fix: bank logins send text as ISO-8859-1 like other FinTS clients (TAN media with umlauts match), and a PIN or TAN with + : ' ? @ no longer breaks the message
- docs: CLAUDE.md, TODO and parity describe the new iOS app
- test: Maestro flows for iOS (onboarding, filter, manual entry with undo, search, 12 months, notifications, Rückblick cards) via scripts/maestro ios
- feat(ios): Rückblick opener: cards with the squirrel for a finished month (what's left, Sparquote, quiet days, a caught price rise), once by itself and any time from the review
- refactor(ios): remove five old components nothing uses anymore (UndoToast, old category editor, month picker, account picker, info tooltip)
- feat(ios): several bank logins: switch between banks, remove one, background refresh fetches from every bank with a saved PIN
- feat(ios): the squirrel in the Übersicht band: its pose says how the month is going, a tap says it in one line, a short moment plays once (Gehalt da, Knapp, Leer, kein Euro raus)
- feat(ios): Wiederkehrend has the 12-month view: paid per month this year, the forecast for the months ahead, a month's payments below
- feat(ios): linking sync checks the key first ("Schlüssel passt nicht") and can scan the QR code; Mitteilungen settings with a quiet time; month-end notice and price-rise notice, a tap opens the page
- feat(ios): English texts for the new Übersicht, Wiederkehrend, Rückblick, Einstellungen, widgets and onboarding; parity notes after the iOS catch-up
- feat(ios): new Übersicht with what's left until the salary, a period sheet (Kalendermonat, Gehaltsmonat, Fester Tag, own range), Wiederkehrend with price changes and one-off payments, and Rückblick in the new look
- feat(ios): bank pages in the new look (connected bank with balance and Schnellabfrage, five-step connect); new app icon, the denim pocket, with dark and tinted versions
- feat(ios): new welcome, first-start choice (bank, file or empty) and lock screen on the dark band, as on Android
- feat(ios): Einstellungen in the new look, grouped as on Android; Zeitraum page to start the month with the salary, on the 1st or a fixed day; Systemsprache as a language choice
- feat(ios): three home screen widgets (Bis zum Gehalt / Monat, Fixkosten offen, Heute) and lock screen widgets in the new look, with hidden amounts as •••• €
- feat(ios): new Suche with the answer in the band and page words; Konten, Gelernte Regeln and Geräte in Einstellungen; statement files (MT940, CAMT) in Import; the old pages in the new colours and fonts
- feat(ios): enter a transaction by hand with + on Umsätze; manual entries can be edited and deleted from their page
- feat(ios): new look on iPhone: tabs Übersicht, Umsätze, Wiederkehrend, Mehr and Suche; Umsätze with filters, booking page, category sheet and undo above the tab bar
- docs: sync server README without the old Cloudflare Worker, with the delete route and the real deploy command
- test: Maestro flows for Back through places, the theme switch and a panel that stays open; the theme switch tells TalkBack which option is on
- fix(ios): category names as in libwimg (Umbuchung, Abonnements), current repo links and FAQ facts, Analyse removed as on Android, setCategory returns how many moved

## v0.9.13 (2026-11-18)

- docs: notes for 0.9.13 (Neuigkeiten, Play What's new, test log)
- feat: "In Umsätzen" opens a search as a filter on Umsätze; Back returns to the same search
- feat: new search: the answer in the band (total, count, average), the merchant, bookings by month; page names open with Enter; jump-to tiles and questions on the start screen
- feat: filter Umsätze to recurring payments only, or include hidden accounts (Weitere)
- feat: filter by amount on Umsätze: under 10 €, over 20 €, over 100 € or your own range, shown under the sum
- docs: TODO, the next Maestro flows
- test: Maestro journeys on the emulator (onboarding into demo data, filter panel, category change and Undo), run with scripts/maestro flow
- fix: onboarding, the empty Übersicht, the + menu and Settings name statement files and Revolut, not only three CSV banks
- docs: TODO, Play upload from CI

## v0.9.12 (2026-11-18)

- docs: Neuigkeiten for 0.9.12 and 0.9.9–0.9.11, Play "What's new" for the next update
- fix: a tap on a panel's empty part no longer closes it, the Design switch shows the chosen mode, and uncategorized bookings say "Unkategorisiert" ("Sonstiges" is the real Other category, as on iOS)
- feat: calmer filter on Umsätze: four rows with their value, short lists for type, account, period and category (only what occurs, by spending), and the sum holds still while scrolling
- fix: changing a booking's category also moves the merchant's other uncategorized bookings, with one undo
- docs: TODO, the GitHub APK key exists
- fix: make-apk-key.sh uses Android Studio's Java when there is no system Java
- fix: make-apk-key.sh checks only the active GitHub account
- docs: Revolut in the store descriptions and tester notes
- fix: the GitHub APK is a release build with its own permanent key, so updates install over the last one
- docs: TODO, Play test updates and the GitHub APK decision
- fix: rules are learned from the merchant, never from a booking word like BELASTUNG; bad learned rules are undone on start
- feat: import Revolut CSV statements (completed EUR current-account rows, fee included, paid date)
- fix: bank search puts ING and other common banks first, and the button says "Ich nutze wimg schon" (tester feedback)
- docs: TODO, the calmer filter panel (brief 19, option A)
- fix: the amount at the top switches instead of rolling when values come fast (scrolling)
- fix: text breaks cleanly (balanced headings, dates and amounts stay together), and the rolling amount no longer shows two minus signs or stray dots
- docs: plainer Play description, with statement files and price notices
- feat: import bank statement files (MT940, CAMT) from any bank, into the same account as the bank connection
- refactor: plain std.debug.print on iOS too, now that Zig 0.17.1 builds it
- fix: pending card payments show the merchant without the payment time
- fix: a bank fetch or CSV import updates fixed costs and their prices right away
- feat: link previews for the website (Open Graph image with demo data)
- docs: closed test log for the Play production form

## v0.9.11 (2026-11-17)

- Version bump

## v0.9.10 (2026-11-17)

- fix: language and theme are set before the first frame, so a cold start never speaks German on an English phone
- fix: a category tapped on Übersicht opens Umsätze with its sum in place, no roll
- fix: back retraces the places opened from the menu instead of jumping to Übersicht
- docs: TODO, moments after the launch animation
- feat: wimg Test can play each squirrel moment and the Rückblick cards on demand; moments wait for the launch animation
- docs: TODO, squirrel leftovers done
- feat: the squirrel's evening moment dims the band and sews today's stitch, payday refills the ring; bar chips never show "…"; 1 transaction
- docs: closed test without asking testers for their bank login
- docs: Play notes match Google's rules (MCP declared, English reviewer steps, test plan); bank login says it goes straight to the bank
- fix: the price notification waits for a rise of at least 1 € and 5 %
- feat: card payments show the merchant ("PAYSEND"), not the bank's card text
- docs: TODO after the price notification, minus-period cards and the English pass
- feat: a period that ended in minus still gets its true Rückblick cards (quiet days, a caught price)
- feat: a notification when a fixed cost gets more expensive, with its own switch
- fix: English reads like English: dates as 15 Nov, day 27 instead of the 27., sentence case, English quotes
- fix: an account without transactions keeps the period and account switch on Übersicht
- fix: the month widget fits at 2×2, writes amounts like the app, and has English names in the widget list
- fix: demo data starts as a salary month with money left, and screen readers hear English category names
- fix: release.sh stops when the push fails instead of saying "Pushed!"

## v0.9.9 (2026-11-16)

- fix: a new install speaks the phone's language, and Neuigkeiten lists 0.9.8
- fix: first start goes straight to the chosen page, without Übersicht flashing or the bar jumping
- refactor: remove the old Cloudflare sync Worker and the WASM build
- docs: TODO lists the price-change notification and the squirrel leftovers

## v0.9.8 (2026-11-16)

- docs: TODO keeps the import-seam sketch; Android section back
- fix: the Rückblick cards also reach under the status bar
- feat: a closed month's review can be replayed as cards any time
- fix: Rückblick opener fills the screen under the system bars; pending dates also from German card texts
- fix: a pending card payment shows the day you paid, not the day wimg fetched it
- docs: Enable Banking ticket sent; auto-reply says no answer without an agreement
- docs: TODO for bank sources: one import seam, file import, CAMT first, Enable Banking pending
- docs: bank access review (Nov 2026): FinTS stays, GoCardless closed, CAMT first, triggers for more
- feat: each bank login keeps its FinTS system id instead of asking for a new one at every sign-in
- fix: bank texts read and written with FinTS escaping everywhere
- fix: phones keep wimg upright; landscape filled the screen with the band and hid the menu under the camera
- docs: field note on Comdirect's random ids and failing MT940; FinTS follow-ups in TODO
- feat: when a bank's MT940 fails, wimg quietly fetches CAMT instead and remembers it
- fix: fints-dump --camt flag no longer clashes with the CAMT result list
- feat: fetch booked statements as CAMT on request; fints-dump gets --until and --camt
- fix: bank ids with escaped characters are read whole and written escaped
- fix: FinTS values escape @ too, so a TAN device name with @ no longer breaks the sign-in
- fix: a saved TAN device goes along whenever the bank requires the name; failed fetches log the TAN parameters
- fix: the bank fetch picks the account that allows statements, not the last one listed
- fix: retrying a bank fetch signs in again instead of sending a sign-in without PIN
- feat: fresh transactions on open and every morning; search finds actions, amounts and wimg's names
- fix: when the bank asks to send again, wimg retries once instead of a misleading CAMT error
- docs: index the field note on the deleted PIN
- fix: a bank hiccup at sign-in no longer deletes the saved PIN
- fix: a fetch without statement names the bank's real reason, not "3060 Warnungen"
- fix: bank and import errors show in the floating bar, not as a box under the fields
- Revert "feat: new landing page: a desk with demo papers, app windows and the squirrel watching you"
- Revert "fix: website desk never cuts things off or covers the buttons; real app screens in the phones, readable install buttons, app icon in the header"
- fix: website desk never cuts things off or covers the buttons; real app screens in the phones, readable install buttons, app icon in the header
- feat: new landing page: a desk with demo papers, app windows and the squirrel watching you
- fix: Rückblick opened straight from a notice shows its numbers at once, never "no transactions" first
- feat: the squirrel plays its moments once and speaks in a bubble; Rückblick opens with up to four cards
- feat: the squirrel sits in the ring next to "Verfügbar"
- refactor: one database schema (version 1) before launch, and dead code removed
- fix: the floating bar never goes pale between pages, and closing search fades too
- docs: field note on the white flash on back; TODO for the bar polish
- fix: no white flash and no wrong bar when going back; ↻ on a bank card fetches in place
- feat: manual entry with the system keyboard and a calendar, menus that match the bar
- feat: manual entries can be edited and deleted, on every device
- perf: smoother page switches, a calmer floating bar and fixes across the Android app
- fix: "Erneut erkennen" keeps your current fixed costs, and pending bookings show up
- feat: Gehaltsmonat — a month can run from one salary to the next (boards 3 and 26A)
- fix: FinTS debug output no longer prints requests (they carry the PIN and TAN)
- fix: pending ("Vorgemerkt") bookings from Comdirect
- feat: wimg Sync shows your devices, scans the key, spots a wrong key and makes a new one (board 21)
- fix: the bank page opens your transactions (Umsätze row and "Ansehen" after a fetch)
- feat: choose an account behind the filter, hide or rename accounts, new settings pages (board 20)
- feat: big band numbers roll to their new value after a change
- fix: going back to Umsätze on the website demo no longer flashes other numbers
- feat: the four phones further down the website can be tapped too
- feat: the demo phone on the website now works like the Android app
- feat: edit recurring payments, hide them, and set aside one-off payments (board 26)
- feat: learned rules page, manual transactions and the Hinzufügen panel (board 22)
- feat: "Alle Daten löschen" also deletes the encrypted copy on the sync server
- docs: Play Store graphics and README screenshots with invented demo data
- docs: Google Play store listing and App content answers
- feat: libwimg functions for learned rules and manual entries
- docs: Google Play publishing notes (personal account, organisation later)
- feat: period ring on Home instead of the month chip
- feat: invented demo merchants, generic keyword rules
- docs: README with screenshots (demo data)
- feat: widget previews in the widget picker on Android
- fix: Android app crashed on start while sync pushed many changes
- fix: bank logins from older builds get their bank name on the Banken page
- fix: umlauts in bank texts (FinTS and Comdirect CSV deliver ISO-8859-1)
- feat: several bank connections on Android
- fix: MCP query tool names the real columns (date_year/month/day, amount_cents)
- feat: lock screen, notifications and widgets from the new design on Android
- docs: describe wimg as it is now (iOS + Android, no web app)
- fix: Umsätze keeps its filter after opening a transaction on Android
- fix: iOS bank login no longer breaks on a PIN with quotes, and never logs it
- refactor: remove the web app, keep translations in i18n/en.ts
- fix: subscription detail is complete from its first frame on Android
- refactor: remove dead code and duplicate helpers in libwimg
- feat: simpler CSV import start on Android
- refactor: remove dead Android code
- feat: pending bank transactions (Vorgemerkt), never imported as booked
- fix: Home transactions open, search keyboard, centred bar buttons
- fix: keyboard, rotation and bank errors on Android
- feat: bank PIN encrypted with the Android Keystore; Umsätze filter by period
- feat: new Rückblick with month-end summary on Android
- feat: fetch older transactions from the bank page on Android
- feat: new Über wimg on Android
- fix: background bank fetch keeps the PIN on hiccups; Analyse removed on Android
- fix: floating bar changes without gaps or squeezing; full-width lock timer
- fix: one floating bar that changes instead of being replaced
- feat: animated launch with the pocket, and safer bank errors on Android
- fix: switching places on Android is instant and clean
- feat: new first start and CSV import on Android
- fix: buttons and chips no longer show dark corners when held
- fix: new app icon and splash, and colours stay right on Xiaomi phones
- fix: smoother floating bar on Android
- feat: new bank connection screens on Android
- feat: new settings on Android
- feat: new search on Android
- feat: fixed-cost details and a 12-month view on Android
- feat: see every past payment of a fixed cost
- feat: new Wiederkehrend screen on Android
- fix: next payment dates for fixed costs were in the wrong month
- fix: Android sync no longer crashes without network and syncs on open
- feat: new look for the Android app — Home, Umsätze and transaction details
- feat: transactions show the merchant instead of the booking type
- feat: new wimg website replaces the web app
- feat: wimg moves to komiljonmaksudov.com
- fix: Android app no longer crashes after a bank refresh
- fix: recurring payments are detected in FinTS bank data
- fix: account balance from the bank syncs to your other devices

## v0.9.7 (2026-11-11)

- fix: FinTS TAN medium lookup runs in its own dialog and returns the device name
- fix: FinTS statement requests work for CAMT-only banks and HKKAZ v7
- fix: FinTS picks the bank's TAN method and handles app approval (pushTAN)

## v0.9.6 (2026-10-22)

- refactor: serve MCP 2026-07-28 only and drop the old session flow
- feat: Claude and other MCP clients can use the 2026-07-28 protocol
- fix: large syncs no longer land under a corrupted sync key
- docs: add AGENTS.md with verified build prerequisites and conventions
- feat: remove the update banner from the Android app

## v0.9.5 (2026-08-05)

- docs: correct stale claims in CLAUDE.md
- feat: background FinTS refresh and notifications on Android
- docs: mark restic backups as an opt-in nice-to-have
- feat: self-host wimg-sync and the web app on Hetzner
- feat: add an app icon to the Android app
- feat: log sync requests to the terminal (key masked)
- feat: self-hosting infra for wimg-sync (Caddy + systemd + restic)
- feat: BIND env to bind the sync server to a specific address
- feat: env-configurable sync server port + native dev mode
- feat: PII scrubbing for MCP query results
- feat: native Zig sync server (HTTP + WebSocket + MCP)

## v0.9.4 (2026-06-23)

- Version bump

## v0.9.3 (2026-06-23)

- feat: show real account balance from FinTS statement
- fix: CSV export silently doing nothing on iOS + Android

## v0.9.2 (2026-05-21)

- fix: FinTS NUL bytes + date UX, refetch auth, categorize feedback
- fix: sync-key validation, PIN confirm focus, lock reset polish
- feat: PIN-vergessen reset on LockScreen + drop dead gguf refs
- feat: add Daten-Browser entry in Settings opening SQL tab

## v0.9.1 (2026-05-19)

- fix: update bank count assertion after catalog trim

## v0.9.0 (2026-05-19)

- feat: settings sync prompt + 4-digit PIN with iOS-style LockScreen
- fix: web credits page + stop passkey sheet popping on every re-lock
- feat: FinTS hub redesign, background fetch, sync key UI, onboarding link

## v0.8.5 (2026-05-17)

- feat: Android parity — 30s background grace + widget masking
- feat: 30s background grace, Cmd+Shift+L lock, widget privacy controls
- feat: localize iOS widget + auto-trigger biometric on web lock screen
- feat: MCP server now exposes one Code Mode `code` tool

## v0.8.4 (2026-05-17)

- feat: native i18n macro, app-lock, supply-chain defense

## v0.8.3 (2026-05-15)

- fix: i18n plugin now translates text="..." attributes

## v0.8.2 (2026-05-15)

- Version bump

## v0.8.1 (2026-05-15)

- Version bump

## v0.8.0 (2026-05-14)

- fix: NetWorthCard month labels follow locale
- fix: AnalysisView count line + heatmap month labels follow locale
- fix: iOS category names + tail-words now follow locale
- fix: top breathing room on sticky Gesamtsaldo card
- refactor: native transactions layout + InfoTooltip + web MCP card
- refactor: align AboutView + AboutScreen with web /about
- feat: infotooltips on analysis page (donut + categories)
- fix: home/transactions polish + Gesamtsaldo placement
- fix: transactions filter scrolls with content; settings card widths
- feat: gesamtsaldo running-balance card on transactions (iOS + Android)
- refactor: prune 140 dead translation keys from en.ts
- fix: stray brace in SearchView.navLink broke iOS build
- feat: add 404 + generic error page
- refactor: remove renewals calendar tab from recurring page
- feat: port dashboard redesign to iOS + Android, rename DashboardView
- fix: iOS recurring pattern strings now actually translate to English
- refactor: revert Verfügbares Einkommen card to pre-Stitch styling
- refactor: separate Gesamtsaldo header from Verfügbar + restore E/A grid
- refactor: wrap balance hero into a single card with internal divider
- feat: combined balance hero on dashboard, add Wiederkehrend quick-link
- refactor: stack Gesamt/Einnahmen/Ausgaben cards into rows
- feat: surface lifetime Gesamtsaldo as 3rd stat card on dashboard
- fix: gap Gesamtsaldo card 4px below app header when sticky
- refactor: restore running-balance logic in Gesamtsaldo card
- feat: make Gesamtsaldo hero card sticky below app header
- feat: replace sticky Saldo bar with Gesamtsaldo hero card on web
- refactor: drop add_account / update_account MCP write tools
- refactor: remove feature flag system entirely
- refactor: remove in-app feedback system
- refactor: drop in-app changelog page, link to GitHub releases instead
- refactor: remove coachmarks system + stray Schulden quick-link
- fix: dismiss InfoTooltip on scroll instead of re-anchoring
- fix: re-anchor InfoTooltip to its trigger on scroll/resize
- fix: use native HTML5 popover for InfoTooltip top-layer rendering
- fix: lift InfoTooltip popover above sibling stacking contexts
- feat: add InfoTooltips on Preisänderungen + Abonnements/Erkennen
- feat: extend InfoTooltips to Net Worth, Heatmap, Monatliche Fixkosten
- feat: restore general-purpose FAQ on About, keep tooltips for cards
- feat: enrich demo data to populate every dashboard card
- feat: replace About FAQ with inline InfoTooltips on cards
- fix: mark stale recurring patterns inactive + tolerate price changes
- refactor: remove tax/goals/debts UI surface across all platforms
- fix: set html lang to de to match German default UI

## v0.7.13 (2026-05-03)

- Version bump

## v0.7.12 (2026-05-03)

- Add no-op SSE on GET /mcp + fix lefthook in worktrees (#4)

## v0.7.11 (2026-04-21)

- feat: enhance Drawer component gesture handling and improve tax page layout

## v0.7.10 (2026-04-17)

- feat: enable DevTools in prod via Ctrl+Shift+D and command palette

## v0.7.9 (2026-04-07)

- feat: add Android home screen widgets, running balance bar, consolidate iOS widgets
- feat: add Large + Lock Screen widgets, include recent transactions

## v0.7.8 (2026-03-31)

- fix: prevent FOUC by loading Google Fonts via <link> instead of CSS @import
- docs: add Phase 8.1 (Home Screen Widgets) + mark Phase 8.0 done

## v0.7.7 (2026-03-29)

- Version bump

## v0.7.6 (2026-03-29)

- fix: iOS performance — move LibWimg calls off main thread + fix tab navigation
- fix: instant feature flag toggles via observable FeatureFlagsState
- fix: reactive locale switching via observable LocaleState
- fix: theme switching via observable ThemeState instead of AppCompatDelegate
- fix: remove duplicate XML string resources — TText handles i18n at runtime
- docs: update feature parity + CLAUDE.md — Android at full iOS parity
- feat: add FinTS Quick Refresh for Android (Phase 6.9 port)
- feat: wire TText into Settings, Tax, Feedback, Transactions, Analysis, Recurring
- feat: add Android i18n — TText component + translation map + XML generator
- feat: add renewals calendar tab to Android RecurringScreen
- feat: wire undo snackbar, coachmarks, account switcher into navigation
- docs: update feature parity — Android now at near-full parity
- fix: limit category editor sheet to 85% height + update CLAUDE.md
- fix: center hero card content across all screens
- feat: add FAQ to About screen + feature toggles to Settings
- feat: Search quick actions + Transactions advanced filter sheet
- perf: iOS reload() via Task.detached + refilter() optimization
- refactor: design polish across all Android screens
- refactor: design polish — iOS-matching theme + Dashboard hero card
- feat: add spending heatmap, coachmarks, feedback for Android
- feat: show changelog in update banner before downloading
- feat: add Feedback screen + fix back callback warning + dialog button color
- fix: data reset with confirmation dialog + WAL/SHM cleanup
- fix: use 2MB stack thread for FinTS calls on Android
- feat: add Sync + FinTS for Android — full JNI bridge + OkHttp
- fix: add missing account C extern declarations + make CategoryEditorSheet internal
- feat: add Search, Onboarding, Account CRUD, Undo toast for Android
- feat: add update checker for Android sideloading
- feat: add Android feature parity — Analysis, Debts, Goals, Recurring, Review, Tax, Settings, About

## v0.7.5 (2026-03-28)

- fix: use debug APK in CI — release APK needs signing config

## v0.7.4 (2026-03-28)

- fix: flatten Android CI artifacts for reliable release attachment

## v0.7.3 (2026-03-28)

- fix: always build Android in CI + landing page download anchor

## v0.7.2 (2026-03-28)

- fix: CI JDK distribution typo + landing page i18n + Android icon

## v0.7.1 (2026-03-28)

- Version bump

## v0.7.0 (2026-03-28)

- feat: add Android app MVP (Phase 8.0a) — Kotlin + Compose + JNI over libwimg

## v0.6.32 (2026-03-28)

- docs: add Codeberg migration as optional/considered in phases
- docs: add iOS i18n rule, update Phase 6.9 status, add TText decision
- fix: smooth PWA update — wait for SW install instead of hard reload
- fix: iOS i18n — use TText(variable) for localization across all views
- feat: add FinTS quick refresh with opt-in PIN storage (Phase 6.9)

## v0.6.31 (2026-03-28)

- fix: allow gh CLI tools in feedback triage Claude action

## v0.6.30 (2026-03-28)

- fix: dark mode white-on-white buttons in iOS + CI deploy-sync WASM dependency

## v0.6.29 (2026-03-28)

- fix: harden FinTS message structure for strict Sparkasse validators
- feat: add renewals calendar tab to iOS RecurringView

## v0.6.28 (2026-03-22)

- feat: add renewals calendar tab to recurring page (Phase 5.4)
- fix: decouple deploy-sync from web build in CI
- fix: simplify deploy-sync condition to not gate on web build result

## v0.6.27 (2026-03-22)

- fix: allow sync deploy when web build is skipped

## v0.6.26 (2026-03-22)

- feat: replace R2 JSON blob with DO SQLite for sync storage
- fix: add workflow_dispatch for manual CI re-runs after failed releases

## v0.6.25 (2026-03-22)

- fix: skip xcstrings generation in CI when bun unavailable

## v0.6.24 (2026-03-22)

- feat: compile-time i18n with custom Vite plugin (German default, English)

## v0.6.23 (2026-03-21)

- feat: contextual onboarding, dark mode fixes, and iOS donut interaction

## v0.6.22 (2026-03-20)

- fix: iOS crash on data reset, FinTS search lag, and post-TAN loading
- feat: Phase 6.8 — Deutsche Bank / Postbank FinTS compatibility

## v0.6.21 (2026-03-19)

- fix: fetch tags and exclude version-bump files in CI change detection

## v0.6.20 (2026-03-19)

- Version bump

## v0.6.19 (2026-03-19)

- fix: resolve double-tap required for navigation in iOS views

## v0.6.18 (2026-03-19)

- Version bump

## v0.6.17 (2026-03-19)

- fix: map label-only 3920 TAN methods for Comdirect
- perf: debounce search and fix DateFormatter allocation in iOS views
- fix: use Array wrapper for Data in fintsSetTanMedium Swift call
- refactor: rewrite FinTS scripts from Python to Bun, remove one-off tests
- feat: harden FinTS TAN medium flow and bank support tooling
- feat: improve top-bank matrix diagnostics and reporting
- fix: harden touchdown token parsing from 3040 responses
- fix: harden CAMT parsing for multi-Ustrd and currency attribute
- feat: add FinTS decoupled TAN and CAMT fallback support
- feat: improve mobile UX and privacy visibility

## v0.6.16 (2026-03-18)

- docs: add TestFlight guide and auto-reset build number in release.sh

## v0.6.15 (2026-03-18)

- docs: add FinTS technical runbook and phase 6.7 plan
- fix: harden FinTS TAN flow and paginated statement import

## v0.6.14 (2026-03-17)

- fix: CI svelte-check errors — exclude test files, a11y fixes, toSorted

## v0.6.13 (2026-03-17)

- docs: add PSD2/PSD3 banking aggregators research
- fix: FinTS dialog ID extraction from HNHBK response + envelope size test fix
- docs: add FinTS protocol learnings to decisions log and phases
- fix: FinTS protocol — HNHBK size patch, HKIDN DEG, segment numbering, Base64
- fix: FinTS protocol — HNHBK size patch off-by-one, segment numbering, no envelope
- fix: FinTS Base64 newline stripping, HKIDN DEG format, Subsembly bank

## v0.6.12 (2026-03-17)

- refactor: remove DrawerIndent page scale effect

## v0.6.11 (2026-03-17)

- fix: feedback verbose errors, full-height snap, selected icon swap
- docs: update CLAUDE.md with Drawer, feedback, bun test, stacked toasts
- fix: feedback triage OIDC permissions and token rename
- refactor: migrate tests from vitest to bun test
- fix: sheet-active class cleanup and BottomNav fly-in transition
- feat: Sonner-style stacked toasts with hover-to-pause and swipe

## v0.6.10 (2026-03-17)

- feat: drawer test page for stacking validation
- fix: theme-color from blue to app background
- feat: in-app feedback → GitHub Issue with rate limiting
- feat: Drawer component with stacking, indent, and portal support

## v0.6.9 (2026-03-16)

- docs: add Sparquote + Heatmap FAQ entries, update project docs
- feat: spending heatmap on analysis page
- feat: Sparquote savings rate card on dashboard

## v0.6.8 (2026-03-14)

- feat: updated onboarding cards + bank nav link in search
- fix: NaN in iOS donut charts from negative expense amounts
- feat: FinTS HTTP callback + deadlock fix + error messages
- feat: iOS dark mode with theme picker

## v0.6.7 (2026-03-14)

- feat: iOS search nav links + FAQ deep-link scroll
- feat: iOS parity — search tab, advanced filters, FAQ sync
- refactor: align iOS tabs with web — 3 tabs, Analyse in More
- docs: fix feature parity — iOS search already implemented
- fix: goals undo/redo, iOS TaxView compile, vitest in CI
- feat: iOS parity — savings goals, tax helper, net worth chart

## v0.6.6 (2026-03-14)

- feat: add vitest tests, custom tax keywords, and extract tax logic
- docs: update CLAUDE.md and rules for Phase 6.3 completion

## v0.6.5 (2026-03-14)

- feat: add Steuern FAQ entry with palette deep-link
- feat: Phase 6.3 — Anlage N tax helper page

## v0.6.4 (2026-03-14)

- fix: show current release notes when version is latest
- docs: defer Phase 6.1 Annual Review to end of year

## v0.6.3 (2026-03-14)

- feat: add savings goals MCP tools + expand FAQ to 19 entries

## v0.6.2 (2026-03-14)

- feat: expand FAQ to 19 entries with palette deep-links

## v0.6.1 (2026-03-14)

- refactor: remove layerchart, improve changelog and palette UX
- feat: add FAQ and MCP help actions to Command Palette

## v0.6.0 (2026-03-14)

- fix: use toSorted() instead of spread+sort in NetWorthChart
- feat: Phase 6.2 — net worth over time chart in analysis page

## v0.5.23 (2026-03-14)

- feat: Phase 6.4 — savings goals
- refactor: remove standalone renewals page
- fix: recurring patterns persist to OPFS, auto-detect on import
- feat: Phase 5.4 — annual renewals calendar

## v0.5.22 (2026-03-14)

- fix: replace afterNavigate with reactive scroll-to-top

## v0.5.21 (2026-03-14)

- fix: scroll to top on page navigation
- fix: scroll lock on navigation, rename dashboard to home
- fix: recurring cards overflow on mobile
- fix: anomaly cards visible in dark mode
- fix: dashboard avatar circle visible in dark mode
- fix: debts header row-wrap on narrow screens
- fix: compact format for large amounts, overflow prevention
- fix: about page hero icon visible in dark mode
- fix: link device input overflow on mobile
- fix: avatar circle stays dark, emerald privacy card dark mode
- fix: primary buttons (bg-text + text-white) invert in dark mode
- fix: accent buttons always show dark text in dark mode
- fix: accent hero cards readable in dark mode
- fix: donut chart center text overflow with compact format
- fix: Toast countdown ring visibility in dark mode
- fix: dark mode hover and selection states
- fix: unify checkbox toggle style across filter sheet and settings
- fix: dark mode for transaction pills, segmented control, filter sheet
- fix: dark mode checkbox toggle contrast, update docs for Phase 5.7b
- fix: dark mode for BottomSheet, Toast, CommandPalette, alerts
- fix: premium dark mode theme matching fintech design
- feat: Phase 5.7b — command palette refinement

## v0.5.20 (2026-03-14)

- fix: Swift argument order and remove unnecessary await
- fix: UpdateBanner shows all missed releases, analysis back icon, Swift type-check

## v0.5.19 (2026-03-14)

- fix: revert Vite+ migration, restore bun + oxfmt/oxlint

## v0.5.18 (2026-03-14)

- feat: add in-app changelog and migrate to Vite+
- fix changelog

## v0.5.17 (2026-03-14)

- Added Phase 5.11: In-App Changelog with a new `/changelog` page that fetches data from the GitHub Releases API, featuring a timeline UI with version badges and commit descriptions.
- Updated UpdateBanner to show inline changelog and modified "Was ist neu?" links to direct to the new `/changelog`.
- Enhanced localStorage caching for offline access after the first fetch.
- Upgraded GitHub Actions from v4 to v6 for checkout and from v4 to v7/v8 for artifact upload/download, improving workflow stability and performance.
- Refactored data clearing functions to remove both "wimg.db" and "e5-small-q8-v7.gguf" files, ensuring a more comprehensive cleanup.

## v0.5.16 (2026-03-14)

- Enhance categorization and UI components

## v0.5.15 (2026-03-14)

- Refactor categorization and remove embedding functionality

## v0.5.14 (2026-03-12)

- Fix tokenizer: replace greedy BPE with Viterbi for Unigram model

## v0.5.13 (2026-03-10)

- Enhance BottomSheet component with improved wheel and touch handling

## v0.5.12 (2026-03-10)

- Refactor tokenizer tests to use helper functions for state reset

## v0.5.11 (2026-03-10)

- Enhance embedding functionality and update documentation

## v0.5.10 (2026-03-09)

- Implement PII stripping in transaction descriptions and enhance transaction filtering

## v0.5.9 (2026-03-09)

- Refactor notifications and enhance category handling in MCP tools

## v0.5.8 (2026-03-09)

- Update release workflow to use the correct path for WASM artifact in GitHub Actions

## v0.5.7 (2026-03-09)

- Enhance WASM build process and add raw SQL query support

## v0.5.6 (2026-03-09)

- Refactor category handling in MCP tools and enhance input fields in settings

## v0.5.5 (2026-03-09)

- Enhance TransactionCard and AboutView components; add MCP connection guide

## v0.5.4 (2026-03-09)

- Optimize WASM memory management for Cloudflare Workers
- Implement monthly snapshots and data export features

## v0.5.3 (2026-03-08)

- Fix migration configuration in wrangler.toml to use new_sqlite_classes for McpSession

## v0.5.2 (2026-03-08)

- Implement feature flags for enhanced user control

## v0.5.1 (2026-03-08)

- Enhance MCP server functionality and UI updates

## v0.5.0 (2026-03-08)

- Implement recurring pattern detection

## v0.4.26 (2026-03-08)

- Add body overflow control in OnboardingOverlay component

## v0.4.25 (2026-03-08)

- Enhance user experience with onboarding and multi-file CSV import features

## v0.4.24 (2026-03-08)

- Enhance encryption and migration features, update transaction handling

## v0.4.23 (2026-03-08)

- Implement Command Palette and enhance encryption features

## v0.4.22 (2026-03-08)

- Fix minor issues in SettingsView and enhance sync functionality

## v0.4.21 (2026-03-08)

- Implement catch-up mechanism for WebSocket reconnections

## v0.4.20 (2026-03-08)

- Enhance database schema and implement soft-delete functionality

## v0.4.19 (2026-03-08)

- Update wrangler.toml to rename 'new_classes' to 'new_sqlite_classes' for clarity in migration configuration

## v0.4.18 (2026-03-08)

- Refactor release workflow to remove conditional steps for wimg-sync changes

## v0.4.17 (2026-03-08)

- Add Phase 6: Financial Clarity features to CLAUDE.md

## v0.4.16 (2026-03-08)

- Implement real-time sync with Cloudflare Durable Objects and WebSocket support

## v0.4.15 (2026-03-07)

- Refactor release workflow to enhance SQLite handling and streamline deployment

## v0.4.14 (2026-03-06)

- Refactor release workflow to streamline SQLite file handling and improve caching

## v0.4.13 (2026-03-06)

- Enhance release workflow by caching SQLite amalgamation and Zig build artifacts

## v0.4.12 (2026-03-06)

- Refactor API key and URL management to use centralized configuration

## v0.4.11 (2026-03-06)

- Enhance file import functionality and update deployment configuration

## v0.4.10 (2026-03-06)

- Add settings, sync worker, JSON unescape fix, and UI improvements

## v0.4.9 (2026-03-06)

- Update Zig test command in release workflow to remove optimization flag for improved consistency

## v0.4.8 (2026-03-06)

- Refactor release process and enhance service worker caching

## v0.4.7 (2026-03-06)

- Enhance release workflow and script with pre-flight checks and Cloudflare Pages project creation

## v0.4.6 (2026-03-06)

- fix svelte-check: add @types/node, a11y labels, empty CSS rule
- release: v0.4.5
- fix oxfmt formatting

## v0.4.5 (2026-03-06)

- fix oxfmt formatting

## v0.4.4 (2026-03-06)

- add release script, changelog, and fix CI sqlite download
- release: v0.4.3
- add release script and changelog

## v0.4.3 (2026-03-06)

- add release script and changelog

## v0.4.2 (2026-03-06)

- Update lefthook configuration and version numbers for iOS and web projects

## v0.4.1 (2026-03-06)

- phase 4A: pure Zig FinTS client + MT940 parser + CI deploy fix

## v0.4.0 (2026-03-06)

- Fix Cloudflare Pages deployment project name in release workflow
- Add Cloudflare Pages deployment to release workflow and update dependencies
- Friendly Finance UI redesign (web + iOS) + Cloudflare Pages deployment
- add landing page at / using SvelteKit layout groups
- phase 3.5: multi-account support + batch CSV processing + emoji fix
- phase 3 complete: iOS app, build scripts, undo/redo, roadmap update
- phase 2 finale: offline SW, CSV preview, CI, bun migration
- phase 3
- phase 1 done
