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
| App access | "All or some functionality is restricted" → add instructions (English, reviewers' phones are usually English): *No account or login needed. On first start tap "Let's go", choose "Start empty", then "Look at demo data" on the empty Overview: every screen then has invented sample data. "Connect bank" talks to German banks via FinTS (registered product ID F7C4049477F6136957A46EC28) and needs the user's own online-banking login; it is optional and the login goes from the phone straight to the bank, never to a wimg server.* |
| Ads | No ads |
| Content rating | Category "All other app types"; answer No to every content question (no violence, no user-generated content shared, no purchases, no gambling). Expected: rated for everyone. |
| Target audience | 18 and over (finance app) |
| News app | No |
| Health apps | No |
| Government app | No |
| Financial features | The declaration has no "personal finance / budgeting" category (checked 2026-11-17). Choose **Support services → Other** and describe: *Personal finance manager. Reads the user's own bank statements from their bank via FinTS, on the device, at the user's request. No lending, payments, transfers, trading or advice.* None of the licensed categories apply. |
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

Answers (checked against Play's Data safety help, 2026-11-17):
- **Sync is not "collected":** end-to-end encrypted data that nobody but the
  user's devices can read is out of scope.
- **MCP is:** when the user connects Claude, the server derives the key from the
  sync key and decrypts the rows in memory for that request. That is ephemeral
  processing, which must be **declared** (it isn't shown on the store page).
  So declare: *Financial info → Other financial info: collected, optional,
  processed ephemerally, purpose App functionality; not shared.*
- **Bank login:** goes from the phone straight to the user's bank at the user's
  request; wimg never receives it. Not declared as collected or shared
  (user-initiated, to a party the user chose). Re-check the wording if Play's
  form asks about credentials.
- Encrypted in transit: **Yes** (TLS; sync additionally end-to-end).
- Users can delete their data: **Yes** (Settings › Data › Delete all data also
  deletes the encrypted copy on the sync server).

## Closed test and production access (personal account)

Rules (Play help, 2026-11-17): 12+ testers opted in for 14 **consecutive** days
(opting out and back in restarts a tester's count), then "Apply for production"
on the Dashboard. Google can ask for 14 more days when testers were too few or
didn't use the app; vendor blogs agree that inactive testers are the usual reason.

- **Testers:** Testers Community (15 testers) plus 3–5 people with a German bank
  account, so the bank connection is tested for real and there is a margin above 12.
- **Tester instructions** (in the test's description and to Testers Community):
  start empty → demo data, then try Overview, Transactions (search, filter, a
  detail), Recurring, Review, the + menu (add a cash entry), Settings, a widget.
  German bank customers: connect your bank. Feedback: the Play "private feedback"
  in the test, or the testing service's report.
- **Keep a feedback log** (date, tester, what, what changed): the form asks for a
  summary and for changes made.
- Ship at least one update during the test that fixes tester feedback.

Draft answers for the application form:
- *Recruiting:* through a testing community plus people I know who bank in Germany.
- *Features used:* demo data covers every screen; the bank connection was tested by
  the German testers and by me (Comdirect, CAMT and MT940). Non-German testers
  can't connect a bank: expected, wimg is for German bank customers.
- *Matches production use:* yes for the screens; real users will mostly connect
  a bank instead of using demo data.
- *Feedback and how collected:* summary from the log.
- *Audience / value:* people in Germany who want to see where their money goes
  without giving a third-party service their bank login. Install estimate: realistic
  and small (e.g. 1,000–10,000 in year one).
- *Changes / readiness:* list the fixes from the log and the release notes.
