# Google Play: store listing and App content answers

Copy-paste source for the Play Console. German is the default language,
English the translation. Limits: name 30, short description 80, full
description 4000 characters.

## Store listing

### App name
`wimg – Wo ist mein Geld?`

### Short description
- **DE:** `Deine Finanzen auf deinem Handy: Bankabruf, Kategorien, Fixkosten. Ohne Konto.`
- **EN:** `Your finances on your phone: bank sync, categories, fixed costs. No account.`

### Full description (DE)

```
wimg zeigt dir, wo dein Geld hingeht – und behält deine Daten dort, wo sie hingehören: auf deinem Handy.

DIREKT VON DEINER BANK
Hol deine Umsätze per FinTS direkt von deiner Bank, ohne Dienst dazwischen. Rund 1.700 deutsche Banken, mit TAN, photoTAN oder Freigabe in der Banking-App. Mehrere Banken gleichzeitig. Oder importiere eine CSV-Datei von Comdirect, Trade Republic oder Scalable.

ÜBERBLICK
• Übersicht: was im Monat noch verfügbar ist, Sparquote, Ausgaben nach Kategorie im Vergleich zum Vormonat
• Umsätze: alle Buchungen nach Tag, mit Suche und Filtern, vorgemerkte Umsätze getrennt
• Wiederkehrend: erkennt Fixkosten und Abos automatisch und meldet Preiserhöhungen
• Rückblick: dein Monat in wenigen Zeilen – was übrig blieb und was auffiel
• Widgets für den Startbildschirm, auf Wunsch ohne Beträge

AUTOMATISCH SORTIERT
Umsätze werden per Stichwort-Regeln Kategorien zugeordnet. Ordnest du etwas von Hand zu, lernt wimg daraus.

DEINE DATEN BLEIBEN BEI DIR
• Alles liegt in einer Datenbank auf deinem Gerät. wimg funktioniert komplett offline.
• Kein Konto, keine Anmeldung bei uns, keine Werbung, kein Tracking, keine Analyse-Dienste.
• Deine Bank-PIN wird nur auf Wunsch gespeichert, verschlüsselt im Android-Schlüsselspeicher.
• Optionaler Abgleich zwischen deinen Geräten, Ende-zu-Ende-verschlüsselt: der Server sieht nur unlesbare Daten.
• App-Sperre mit Fingerabdruck oder Geräte-PIN.

OPEN SOURCE
wimg ist quelloffen (MIT-Lizenz). Den Code findest du auf GitHub.
```

### Full description (EN)

```
wimg shows you where your money goes – and keeps your data where it belongs: on your phone.

STRAIGHT FROM YOUR BANK
Fetch your transactions directly from your bank via FinTS, with no service in between. About 1,700 German banks, with TAN, photoTAN or approval in your banking app. Several banks at once. Or import a CSV file from Comdirect, Trade Republic or Scalable.

OVERVIEW
• Overview: what's left this month, savings rate, spending by category compared with last month
• Transactions: every booking by day, with search and filters, pending bookings shown apart
• Recurring: detects fixed costs and subscriptions and flags price increases
• Review: your month in a few lines – what was left over and what stood out
• Home screen widgets, optionally without amounts

SORTED AUTOMATICALLY
Transactions are assigned to categories by keyword rules. When you change one by hand, wimg learns from it.

YOUR DATA STAYS WITH YOU
• Everything lives in a database on your device. wimg works fully offline.
• No account, no sign-up with us, no ads, no tracking, no analytics.
• Your bank PIN is only saved if you want, encrypted in the Android keystore.
• Optional sync between your devices, end-to-end encrypted: the server only sees unreadable data.
• App lock with fingerprint or device PIN.

OPEN SOURCE
wimg is open source (MIT licence). The code is on GitHub.
```

### Graphics
- App icon 512 × 512, feature graphic 1024 × 500, phone screenshots:
  `docs/play-store/` (demo data only).

## App content

| Section | Answer |
| --- | --- |
| Privacy policy | `https://wimg.komiljonmaksudov.com/datenschutz.html` |
| App access | "All or some functionality is restricted" → add instructions: *No login needed. On first start choose "Leer starten", then tap "Beispieldaten ansehen" on the empty Übersicht. Connecting a bank needs the user's own online-banking login; it is optional.* |
| Ads | No ads |
| Content rating | Category "All other app types"; answer No to every content question (no violence, no user-generated content shared, no purchases, no gambling). Expected: rated for everyone. |
| Target audience | 18 and over (finance app) |
| News app | No |
| Health apps | No |
| Government app | No |
| Financial features | Declare: personal finance – budgeting / expense tracking. No lending, no payments, no crypto, no banking services of its own. Note: it reads the user's own bank statements directly from the bank (FinTS) on the device. |
| Data safety | See below |

### Data safety (please read before submitting – this is your declaration)

How wimg handles data:
- Transactions, categories, rules and settings stay on the device.
- **Bank access:** the app sends the user's bank login (and TAN) directly to
  the user's own bank, at the user's request, to fetch statements. Nothing
  passes through a wimg server.
- **Sync (optional, off by default):** transaction data is sent to the wimg
  sync server **end-to-end encrypted** (the server cannot read it).
- **MCP (optional):** only if the user connects Claude to the sync server
  themselves; then decrypted data goes to that AI service at the user's request.
- No analytics, no crash reporting SDK, no ads, no third-party SDKs.

Suggested answers:
- "Does your app collect or share any of the required user data types?" →
  **No.** Google's guidance exempts data that is processed only on the device,
  data the user sends to a third party of their choice (their bank), and data
  sent end-to-end encrypted. Check the current wording in Play's "Data safety"
  help before answering; if in doubt, declare "Financial info → Purchase history /
  other financial info: collected, optional, encrypted in transit, not shared"
  for the sync feature.
- Encrypted in transit: **Yes** (TLS; sync additionally end-to-end).
- Users can delete their data: **Yes** (Einstellungen › Daten › Alle Daten
  löschen; sync data via ending sync).
