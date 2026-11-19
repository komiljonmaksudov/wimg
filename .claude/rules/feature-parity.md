# Feature Parity — iOS vs Android

Both apps are thin shells over the same libwimg C ABI. The web app was removed
in Nov 2026; `wimg.komiljonmaksudov.com` is a static landing page (`wimg-site/`).

## At Parity

Dashboard (+ Sparquote), Transactions (+ filters), Recurring,
Monthly Review (Rückblick), CSV Import, Auto-categorization + learned rules,
Search, Settings (theme, language, sync, data export/reset), About, Onboarding,
App lock (biometric / device PIN), FinTS (bank search, credentials, TAN, TAN
medium, statement fetch), Quick Refresh with stored PIN, background refresh +
notifications, Sync (WebSocket + HTTP push/pull + E2E encryption, QR linking),
Home screen widgets, Demo data, Undo/redo, Gehaltsmonat, Systemsprache,
Recurring decisions (hide, edit, one-off, accept price), Accounts hide/rename,
12-month recurring forecast, Notification settings + quiet time, Month-end and
price-rise notices, Sync key check + QR scan, Several bank logins, the squirrel
in the band (iOS: poses + moments; Rückblick opener cards only on Android), Pending transactions
("Vorgemerkt"), Manual entries (add, edit, delete, "Von Hand" filter).

Tax, Goals, Debts UI removed 2026-05-14; Feedback removed later; Analyse removed
on both (iOS 2026-11-19). libwimg keeps the debt/goal C ABI + tables.

iOS redesign (brief 22) done on 2026-11-19: every screen, the widgets and the
app icon are in the new look. Also on both now: Gehaltsmonat, recurring decisions
(hide, edit, one-off, accept price), accounts hide/rename, Systemsprache, sync
devices and new key. Seen only in the iOS 18 simulator so far, not on iOS 26 or a
phone; widgets not seen on a home screen.

## Differences

| Feature                                  | iOS | Android | Note                                        |
| ---------------------------------------- | --- | ------- | ------------------------------------------- |
| Update checker (GitHub Releases)         | no  | yes     | iOS uses TestFlight                          |
| Navigation                               | 4 tabs (Übersicht, Umsätze, Wiederkehrend, Mehr) + search tab | one floating bar + places menu | brief 22 option A |
| Page actions (filter, +, category)       | round buttons in the band, top right | chips in the floating bar | |
| Stored bank PIN                          | Keychain `fints_pin` | Keystore AES-256-GCM (`PinStore.kt`) | |
| Background refresh                       | `BGAppRefreshTask` | WorkManager daily | |

## Remote

MCP server (`POST /mcp` on `wimg-sync-zig`): `query` + `set_category`.
