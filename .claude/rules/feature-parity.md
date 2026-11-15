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
Home screen widgets, Demo data, Undo/redo.

Tax, Goals, Debts UI removed 2026-05-14; Feedback removed later. libwimg keeps
the debt/goal C ABI + tables.

## Differences

| Feature                                  | iOS | Android | Note                                        |
| ---------------------------------------- | --- | ------- | ------------------------------------------- |
| Analyse (net worth, spending heatmap)    | yes | no      | Removed on Android                           |
| Recurring 12-month forecast            | no  | yes     | "12 Monate" view on RecurringScreen         |
| Pending transactions ("Vorgemerkt")      | no  | yes     | `wimg_get_pending`, iOS not wired yet        |
| Recurring: hide, edit, one-off payments  | no  | yes     | board 26; libwimg + sync done, iOS UI not    |
| Accounts: hide/show, rename, picker      | no  | yes     | board 20; `accounts.hidden` synced, iOS UI not |
| Notification settings (per kind, quiet time) | no | yes  | board 20; Android prefs only                 |
| Language "Systemsprache"                 | no  | yes     | board 20                                     |
| Sync: device list, remove device, new key, QR scan, wrong-key check | no | yes | board 21; `sync_devices` in libwimg |
| Gehaltsmonat (salary / fixed-day periods) | no | yes     | boards 3 + 26A; detection and periods in libwimg `period.zig` |
| Manual entries: edit, delete, "Von Hand" filter | no | yes  | libwimg v22 (`source`, `deleted_transactions`), iOS UI not yet |
| Squirrel in the band: moments + bubble, Rückblick opener | no | yes | `Squirrel.kt`, `ReviewOpener.kt`; played once each (prefs `wimg_moments`) |
| Update checker (GitHub Releases)         | no  | yes     | iOS uses TestFlight                          |
| Navigation                               | 4 tabs (Suche, Home, Umsätze, Mehr) | one floating bar + places menu | |
| Stored bank PIN                          | Keychain `fints_pin` | Keystore AES-256-GCM (`PinStore.kt`) | |
| Background refresh                       | `BGAppRefreshTask` | WorkManager daily | |

## Remote

MCP server (`POST /mcp` on `wimg-sync-zig`): `query` + `set_category`.
