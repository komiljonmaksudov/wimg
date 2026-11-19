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
Recurring decisions (hide, edit, one-off, accept price), Accounts hide/rename, Pending transactions
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
| Recurring 12-month forecast            | no  | yes     | "12 Monate" view on RecurringScreen         |
| Notification settings (per kind, quiet time) | no | yes  | board 20; Android prefs only                 |
| Sync: wrong-key check before linking, QR scan | no | yes | board 21; device list, remove device, new key are on both |
| Squirrel in the band: moments + bubble, Rückblick opener | no | yes | `Squirrel.kt`, `ReviewOpener.kt`; played once each (prefs `wimg_moments`) |
| Several bank logins                      | no (one) | yes | iOS keeps one login in the Keychain (fints_blz/kennung/pin) |
| Month-end notice ("Dein Oktober ist abgeschlossen") | no | yes | `MonthEndWorker` |
| Update checker (GitHub Releases)         | no  | yes     | iOS uses TestFlight                          |
| Navigation                               | 4 tabs (Übersicht, Umsätze, Wiederkehrend, Mehr) + search tab | one floating bar + places menu | brief 22 option A |
| Page actions (filter, +, category)       | round buttons in the band, top right | chips in the floating bar | |
| Stored bank PIN                          | Keychain `fints_pin` | Keystore AES-256-GCM (`PinStore.kt`) | |
| Background refresh                       | `BGAppRefreshTask` | WorkManager daily | |

## Remote

MCP server (`POST /mcp` on `wimg-sync-zig`): `query` + `set_category`.
