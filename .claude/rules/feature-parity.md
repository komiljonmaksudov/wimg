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
Home screen widgets, Demo data, Undo/redo, Pending transactions
("Vorgemerkt"), Manual entries (add, edit, delete, "Von Hand" filter).

Tax, Goals, Debts UI removed 2026-05-14; Feedback removed later; Analyse removed
on both (iOS 2026-11-19). libwimg keeps the debt/goal C ABI + tables.

iOS redesign (brief 22) in progress: tabs, Mehr, Umsätze (filters, booking page,
category sheet, Dock) and manual entries are done; Übersicht, Wiederkehrend,
Suche, Settings pages, Banken, Rückblick, onboarding and widgets still have the
old look.

## Differences

| Feature                                  | iOS | Android | Note                                        |
| ---------------------------------------- | --- | ------- | ------------------------------------------- |
| Recurring 12-month forecast            | no  | yes     | "12 Monate" view on RecurringScreen         |
| Recurring: hide, edit, one-off payments  | no  | yes     | board 26; libwimg + sync done, iOS UI not    |
| Accounts: hide/show, rename, picker      | no  | yes     | board 20; `accounts.hidden` synced, iOS UI not |
| Notification settings (per kind, quiet time) | no | yes  | board 20; Android prefs only                 |
| Language "Systemsprache"                 | no  | yes     | board 20                                     |
| Sync: device list, remove device, new key, QR scan, wrong-key check | no | yes | board 21; `sync_devices` in libwimg |
| Gehaltsmonat (salary / fixed-day periods) | no | yes     | boards 3 + 26A; detection and periods in libwimg `period.zig` |
| Squirrel in the band: moments + bubble, Rückblick opener | no | yes | `Squirrel.kt`, `ReviewOpener.kt`; played once each (prefs `wimg_moments`) |
| Update checker (GitHub Releases)         | no  | yes     | iOS uses TestFlight                          |
| Navigation                               | 4 tabs (Übersicht, Umsätze, Wiederkehrend, Mehr) + search tab | one floating bar + places menu | brief 22 option A |
| Page actions (filter, +, category)       | round buttons in the band, top right | chips in the floating bar | |
| Stored bank PIN                          | Keychain `fints_pin` | Keystore AES-256-GCM (`PinStore.kt`) | |
| Background refresh                       | `BGAppRefreshTask` | WorkManager daily | |

## Remote

MCP server (`POST /mcp` on `wimg-sync-zig`): `query` + `set_category`.
