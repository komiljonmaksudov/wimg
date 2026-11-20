# App Store: listing and App Store Connect answers

Copy-paste source for App Store Connect (iPhone only). German is the primary
language, English the second. Limits: name 30, subtitle 30, promotional text 170,
keywords 100 (comma-separated, no spaces needed), description 4000 characters.
Screenshots: `docs/app-store/<lang>/6.3/` (1206 × 2622, the **required** size since
Apple's 2026 rules) and `docs/app-store/<lang>/6.9/` (1320 × 2868, optional), demo data
only, made by `.maestro/store/screens.yaml` (command in that file; 6.3 is the default
simulator, 6.9 needs `WIMG_IOS_SIM=wimg-store WIMG_IOS_MODEL="iPhone 16 Pro Max"`).

## Store listing

### Name
`wimg – Wo ist mein Geld?`

### Subtitle
- **DE:** `Deine Bank, ohne Umweg`
- **EN:** `Your bank, no middleman`

### Promotional text
- **DE:** `Hol deine Umsätze direkt von deiner Bank, sieh, was bis zum Gehalt bleibt, und finde Abos, die teurer werden. Alles bleibt auf deinem iPhone.`
- **EN:** `Fetch your transactions straight from your bank, see what's left until payday and spot subscriptions that got dearer. Everything stays on your iPhone.`

### Keywords
- **DE:** `Haushaltsbuch,Finanzen,Ausgaben,Budget,FinTS,Konto,Bank,Comdirect,Sparkasse,Fixkosten,Abo,Gehalt`
- **EN:** `budget,expenses,finance,bank,FinTS,German bank,Comdirect,Sparkasse,subscriptions,salary,spending`

### Description (DE)

```
wimg zeigt dir, wo dein Geld hingeht. Deine Daten bleiben auf deinem iPhone.

DIREKT VON DEINER BANK
Hol deine Umsätze per FinTS direkt von deiner Bank, ohne Dienst dazwischen. Rund 1.700 deutsche Banken, mit TAN, photoTAN oder Freigabe in der Banking-App. Mehrere Banken gleichzeitig. Oder importiere einen Kontoauszug (MT940, CAMT) von jeder Bank oder eine CSV-Datei von Comdirect, Trade Republic, Scalable oder Revolut.

WAS DU SIEHST
• Übersicht: was bis zum Gehalt noch verfügbar ist, Sparquote, Ausgaben nach Kategorie im Vergleich zum Monat davor
• Umsätze: alle Buchungen nach Tag, mit Suche und Filtern, vorgemerkte Umsätze getrennt
• Wiederkehrend: erkennt Fixkosten und Abos und sagt dir Bescheid, wenn ein Preis steigt
• Rückblick: was am Ende übrig blieb und was auffiel
• Widgets für Home- und Sperrbildschirm, auf Wunsch ohne Beträge

AUTOMATISCH SORTIERT
wimg ordnet Umsätze per Stichwort-Regeln Kategorien zu. Ordnest du etwas von Hand zu, lernt wimg daraus.

DEINE DATEN BLEIBEN BEI DIR
• Alles wird auf deinem iPhone gespeichert. wimg funktioniert komplett offline.
• Kein Konto, keine Werbung, kein Tracking, keine Analyse-Dienste.
• Deine Bank-PIN wird nur auf Wunsch gespeichert, im iOS-Schlüsselbund.
• Optionaler Abgleich zwischen deinen Geräten, Ende-zu-Ende-verschlüsselt: der Server sieht nur unlesbare Daten.
• App-Sperre mit Face ID, Touch ID oder Gerätecode.

OPEN SOURCE
wimg ist quelloffen (MIT-Lizenz). Den Code findest du auf GitHub.
```

### Description (EN)

```
wimg shows you where your money goes. Your data stays on your iPhone.

STRAIGHT FROM YOUR BANK
Fetch your transactions directly from your bank via FinTS, with no service in between. About 1,700 German banks, with TAN, photoTAN or approval in your banking app. Several banks at once. Or import a bank statement (MT940, CAMT) from any bank, or a CSV file from Comdirect, Trade Republic, Scalable or Revolut.

WHAT YOU SEE
• Overview: what's left until payday, savings rate, spending by category compared with the month before
• Transactions: every booking by day, with search and filters, pending bookings shown apart
• Recurring: detects fixed costs and subscriptions and tells you when a price goes up
• Review: what was left over at the end and what stood out
• Widgets for the Home and Lock Screen, optionally without amounts

SORTED AUTOMATICALLY
wimg sorts transactions into categories by keyword rules. When you change one by hand, wimg learns from it.

YOUR DATA STAYS WITH YOU
• Everything is stored on your iPhone. wimg works fully offline.
• No account, no ads, no tracking, no analytics.
• Your bank PIN is only saved if you want, in the iOS Keychain.
• Optional sync between your devices, end-to-end encrypted: the server only sees unreadable data.
• App lock with Face ID, Touch ID or your passcode.

OPEN SOURCE
wimg is open source (MIT licence). The code is on GitHub.
```

### URLs
- Privacy policy: DE `https://wimg.komiljonmaksudov.com/datenschutz.html`, EN `https://wimg.komiljonmaksudov.com/privacy.html`
- Support: `https://github.com/komiljonmaksudov/wimg/issues`
- Marketing (optional): `https://wimg.komiljonmaksudov.com`

## App Review information

- Sign-in required: **No**.
- Notes (English):

```
No account or login is needed. On first start tap "Let's go", choose "Start empty", then "Look at demo data" on the empty Overview: every screen then shows invented sample data.

"Connect bank" (More › Banks) talks to German banks via FinTS, the German online-banking standard (registered FinTS product ID with Die Deutsche Kreditwirtschaft). It needs the user's own German online-banking login and is optional. The login goes from the phone straight to the user's bank; it never reaches a wimg server.

wimg Sync (Settings) is optional and end-to-end encrypted. The camera is used only to scan a sync key QR code.
```

## App Privacy (App Store Connect) — your declaration, read before submitting

Answer: **"No, we do not collect data from this app."** Apple's definition
(developer.apple.com/app-store/app-privacy-details, checked 2026-11-20): "Collect"
means transmitting data off the device and storing it in a readable form for
longer than it takes to service the request; data sent to a server and discarded
after servicing the request needs no disclosure.
- Sync: stored only end-to-end encrypted, not readable → not collected.
- Claude via MCP (optional): decrypted in memory for one request, nothing readable
  kept → not collected (Apple's own example). Google Play's Data safety is
  stricter and does declare it (`docs/play-store-listing.md`).
- Bank login and TAN: from the phone to the user's bank, never to wimg.
- Tracking: **No**. `wimg-ios/wimg/PrivacyInfo.xcprivacy` declares no collected
  data; keep the two in step.

## Other questions
- Age rating: answer **None / No** everywhere.
- Price: free; all countries where German banks matter, or all.
- EU Digital Services Act trader status: free app, no income → **not a trader**
  (otherwise Apple shows address and phone). Revisit if wimg earns money.
- Export compliance (decided 2026-11-20): libwimg's own XChaCha20-Poly1305 is a
  standard algorithm not provided by iOS → French encryption declaration only for
  France, so France is left out. `ITSAppUsesNonExemptEncryption: true`; per build
  answer "standard encryption algorithms instead of, or in addition to, Apple's".
