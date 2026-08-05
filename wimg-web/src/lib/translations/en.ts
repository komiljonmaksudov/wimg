/**
 * English translations — German key → English value.
 * Only strings that differ need entries. Missing keys fall back to German.
 */
export const en: Record<string, string> = {
  // Interpolated keys (iOS #L macro uses %@ placeholders; web plugin ignores these)
  "%@ Transaktionen": "%@ transactions",
  "%@ Umsätze": "%@ transactions",
  "%@ erkannte Muster": "%@ detected patterns",
  "Du sparst %@ von %@": "You save %@ of %@",
  "· Zuletzt: %@": "· Last: %@",
  "Mehr laden (%@ weitere)": "Load more (%@ more)",
  "%@: +%@ (%@% mehr)": "%@: +%@ (%@% more)",
  "Vormonat: %@": "Last month: %@",
  "Aktuell: %@": "Current: %@",
  "am %@": "on %@",
  "%@ Rückblick": "%@ Review",

  // Navigation / Bottom Nav
  Umsätze: "Transactions",
  Mehr: "More",
  Suche: "Search",

  // Layout
  "Initialisierung fehlgeschlagen": "Initialization failed",
  "Update verfügbar — jetzt aktualisieren": "Update available — update now",
  "Seite neu laden": "Reload page",

  // Error / 404 page
  "Ups! Seite nicht gefunden": "Oops! Page not found",
  "Etwas ist schiefgelaufen": "Something went wrong",
  "Der digitale Pfad endet hier. Vielleicht wurde die Seite verschoben oder du hast dich vertippt.":
    "The digital path ends here. The page may have been moved or you mistyped the URL.",
  "Wir konnten die Seite nicht laden. Bitte versuche es erneut.":
    "We couldn't load the page. Please try again.",
  "404 Error": "404 Error",
  "Zurück zum Dashboard": "Back to Dashboard",
  "Support kontaktieren": "Contact Support",

  // Dashboard
  "Willkommen zurück": "Welcome back",
  "Guten Morgen": "Good morning",
  "Guten Tag": "Good afternoon",
  "Guten Abend": "Good evening",
  "Willkommen bei wimg": "Welcome to wimg",
  "Importiere eine CSV-Datei oder lade Beispieldaten, um loszulegen.":
    "Import a CSV file or load sample data to get started.",
  "CSV importieren": "Import CSV",
  "Beispieldaten laden": "Load sample data",
  "Lade...": "Loading...",
  "Verfügbares Einkommen": "Available Income",
  "vs. Vormonat": "vs. last month",
  Einnahmen: "Income",
  Ausgaben: "Expenses",
  Sparquote: "Savings Rate",
  "Du sparst": "You save",
  "pp vs. Vormonat": "pp vs. last month",
  "Budget Übersicht": "Budget Overview",
  Details: "Details",
  Total: "Total",
  "Letzte Transaktionen": "Recent Transactions",
  Alle: "All",
  Sonstiges: "Other",
  "Keine Daten für diesen Monat": "No data for this month",
  "um zu starten": "to get started",

  // More page
  Analyse: "Analysis",
  Schulden: "Debts",
  Wiederkehrend: "Recurring",
  Rückblick: "Review",
  Einstellungen: "Settings",
  "Über wimg": "About wimg",

  // Analysis
  Insights: "Insights",
  "Noch keine Daten": "No data yet",
  "Importiere eine CSV-Datei, um deine Ausgaben zu analysieren.":
    "Import a CSV file to analyze your spending.",
  "Ausgaben nach Kategorie": "Spending by Category",
  "Übersicht deiner Ausgaben für den gewählten Monat: Verteilung nach Kategorie, Nettovermögen über die Zeit und Ausgaben-Heatmap.":
    "Overview of your spending for the selected month: category breakdown, net worth over time, and spending heatmap.",
  "Zeigt deine Ausgaben des Monats aufgeschlüsselt nach Kategorie. Tippe ein Segment für Details.":
    "Shows your monthly spending broken down by category. Tap a segment for details.",
  "Alle Ausgabenkategorien dieses Monats, absteigend nach Betrag. Tippe eine Kategorie für ihre Transaktionen.":
    "All spending categories for this month, sorted by amount descending. Tap a category to see its transactions.",
  Verfügbar: "Available",
  Kategorien: "Categories",
  "Keine Transaktionen": "No transactions",
  "Keine Daten": "No data",

  // Widget (iOS WidgetKit / Android Glance)
  "Öffne wimg": "Open wimg",
  "wimg — Öffne App": "wimg — Open app",
  "Nächste Zahlung": "Next payment",
  "Letzte Buchungen": "Recent transactions",
  "Verfügbares Einkommen, Sparquote & letzte Buchungen":
    "Available income, savings rate & recent transactions",
  "Beträge in Widgets ausblenden": "Hide amounts in widgets",
  "Zeigt ••• € statt echter Beträge.": "Shows ••• € instead of real amounts.",
  "Zeigt ••• € statt echter Beträge. Sperrbildschirm-Widget wird zusätzlich von iOS verdeckt, wenn das Gerät gesperrt ist.":
    "Shows ••• € instead of real amounts. The lock-screen widget is additionally redacted by iOS while the device is locked.",
  "Für diesen Monat liegen keine Ausgaben vor": "No expenses for this month",

  // Transactions
  "Änderungen gespeichert": "Changes saved",
  Gesamtsaldo: "Total Balance",
  Kontostand: "Account Balance",
  "Transaktion im Blickfeld": "transaction in view",
  "Transaktionen im Blickfeld": "transactions in view",
  Suchen: "Search",
  Filter: "Filter",
  "Importiere eine CSV-Datei um loszulegen": "Import a CSV file to get started",
  "Keine Ergebnisse": "No results",
  "Versuche einen anderen Filter": "Try a different filter",
  "Suchen nach...": "Search for...",
  Zeitraum: "Time Period",
  "Letzte 30 Tage": "Last 30 days",
  "Aktueller Monat": "Current month",
  "Letztes Quartal": "Last quarter",
  Von: "From",
  Bis: "To",
  Zurücksetzen: "Reset",
  Betrag: "Amount",
  "Ausgeblendete anzeigen": "Show hidden",
  "Ergebnisse anzeigen": "Show results",
  Kategorie: "Category",
  "Transaktion einblenden": "Show transaction",
  "Transaktion ausblenden": "Hide transaction",
  Fertig: "Done",

  // Settings
  Synchronisierung: "Sync",
  "E2E-verschl.": "E2E encrypted",
  "Daten zwischen Geräten synchronisieren": "Sync data between devices",
  "Kein Internet — Sync nicht verfügbar": "No internet — Sync unavailable",
  "Sync aktivieren": "Enable Sync",
  "Sync-Schlüssel": "Sync Key",
  "Schlüssel verbergen": "Hide key",
  "Schlüssel anzeigen": "Show key",
  "Schlüssel kopieren": "Copy key",
  "QR-Code anzeigen": "Show QR code",
  "Letzte Sync": "Last Sync",
  "Synchronisiere...": "Syncing...",
  Offline: "Offline",
  "Jetzt synchronisieren": "Sync now",
  "Gerät verknüpfen": "Link Device",
  "Sync-Schlüssel einfügen": "Paste sync key",
  Verknüpfen: "Link",
  Features: "Features",
  Sprache: "Language",
  Regeln: "Rules",
  "Automatische Kategorisierung": "Automatic categorization",
  "Noch keine Regeln. Regeln werden automatisch erstellt, wenn du Transaktionen kategorisierst.":
    "No rules yet. Rules are created automatically when you categorize transactions.",
  "Gelernte Regeln": "Learned Rules",
  "Regel löschen": "Delete rule",
  "Standard-Regeln": "Default Rules",
  "Daten exportieren": "Export Data",
  "Transaktionen als CSV oder komplettes Backup": "Transactions as CSV or full backup",
  "Demo-Daten": "Demo Data",
  Aktiv: "Active",
  "Beispieldaten sind geladen": "Sample data loaded",
  "Demo-Daten löschen": "Delete demo data",
  "Daten zurücksetzen": "Reset Data",
  "Lokale Datenbank, Sync-Daten & alte Modelle löschen":
    "Delete local database, sync data & old models",
  "Alle Daten löschen": "Delete all data",
  "Noch nie": "Never",

  // Settings — Sync Info Sheet
  "Daten zwischen Geräten teilen": "Share data between devices",
  "Echtzeit-Synchronisierung": "Real-time Sync",
  "Änderungen erscheinen sofort auf allen verbundenen Geräten.":
    "Changes appear instantly on all connected devices.",
  "Ein Schlüssel, kein Konto": "One key, no account",
  "Ein zufälliger Sync-Schlüssel wird erstellt. Kein Konto, kein Passwort.":
    "A random sync key is generated. No account, no password.",
  "Schlüssel geheim halten": "Keep your key secret",
  "Wer den Schlüssel hat, kann deine Daten sehen. Teile ihn nur mit deinen eigenen Geräten.":
    "Anyone with the key can see your data. Only share it with your own devices.",
  "MCP für KI-Agenten": "MCP for AI Agents",
  "Dein Sync-Schlüssel dient auch als MCP-Zugang. Claude.ai kann deine Finanzdaten abfragen und verwalten. Personenbezogene Daten (IBANs, Kartennummern, Namen) werden automatisch entfernt.":
    "Your sync key also serves as MCP access. Claude.ai can query and manage your financial data. Personal data (IBANs, card numbers, names) is automatically removed.",
  "Aktiviere...": "Enabling...",
  Abbrechen: "Cancel",
  "Neuen Sync-Schlüssel erstellen": "Create new sync key",
  "Erstellt einen zufälligen Schlüssel und lädt deine Daten hoch. Du kannst ihn auf weiteren Geräten verwenden, um sie zu verknüpfen.":
    "Generates a random key and uploads your data. You can use it on other devices to link them.",
  oder: "or",
  "Ungültiger Sync-Schlüssel.": "Invalid sync key.",

  // Settings — QR / Link / Delete sheets
  "Scanne diesen Code auf dem anderen Gerät": "Scan this code on the other device",
  "Gerät verknüpfen?": "Link device?",
  "Dieses Gerät mit folgendem Sync-Schlüssel verbinden:":
    "Connect this device with the following sync key:",
  "Alle Daten löschen?": "Delete all data?",
  "Alle lokalen Daten werden unwiderruflich gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.":
    "All local data will be permanently deleted. This action cannot be undone.",
  "Lösche...": "Deleting...",
  "Ja, alles löschen": "Yes, delete everything",
  "Deine Daten gehören dir": "Your data belongs to you",
  "Transaktionen (CSV)": "Transactions (CSV)",
  "Alle Transaktionen als Tabelle. Perfekt für Excel, Numbers oder Google Sheets.":
    "All transactions as a table. Perfect for Excel, Numbers or Google Sheets.",
  "Datum, Beschreibung, Betrag, Kategorie, Konto": "Date, Description, Amount, Category, Account",
  "Komplettes Backup (JSON)": "Full Backup (JSON)",
  "Die gesamte Datenbank als JSON-Datei. Enthält alle Konten, Transaktionen, Schulden und Regeln.":
    "The entire database as a JSON file. Contains all accounts, transactions, debts and rules.",
  "Maschinenlesbar, ideal als Sicherungskopie": "Machine-readable, ideal as backup",
  Schliessen: "Close",
  Schließen: "Close",

  // Debts
  Hinzufügen: "Add",
  Löschen: "Delete",

  // Goals
  Icon: "Icon",
  Sparen: "Save",
  Speichern: "Save",
  Zurück: "Back",

  // Import
  "CSV Import": "CSV Import",
  "Analysiere...": "Analyzing...",
  "CSV hochladen": "Upload CSV",
  "Ziehe deine Bankdatei hierhin oder tippe zum Durchsuchen":
    "Drag your bank file here or tap to browse",
  "Datei auswählen": "Choose file",
  "Unterstützte Formate": "Supported formats",
  "Semikolon, ISO-8859-1": "Semicolon, ISO-8859-1",
  "Komma, UTF-8": "Comma, UTF-8",
  "Semikolon, UTF-8": "Semicolon, UTF-8",
  "Andere Datei hochladen": "Upload another file",
  Buchungen: "Transactions",
  Weniger: "Less",
  "Alle anzeigen": "Show all",
  "Import abgeschlossen": "Import complete",
  "Weitere Datei importieren": "Import another file",
  Kategorisierung: "Categorization",
  "Tippe auf eine Buchung, um eine Kategorie zuzuweisen.":
    "Tap a transaction to assign a category.",
  "Auswahl beenden": "Done",
  "Mehrere auswählen": "Select multiple",
  "Alle auswählen": "Select all",
  "Kategorie zuweisen": "Assign category",
  "Alle Buchungen kategorisiert": "All transactions categorized",
  "Zukünftige Importe profitieren von diesen Zuordnungen.":
    "Future imports will use these category rules.",
  "Zum Dashboard →": "Go to Dashboard →",
  "Transaktionen ansehen →": "View Transactions →",
  "Kategorie für alle zuweisen": "Assign category for all",
  "Kategorie wählen": "Choose category",
  "Duplikat-Hinweis": "Duplicate notice",
  Unbekannt: "Unknown",
  "Parsing fehlgeschlagen": "Parsing failed",
  "Import fehlgeschlagen": "Import failed",

  // Review
  Gespart: "Saved",
  Defizit: "Deficit",
  "Top Kategorien": "Top Categories",
  "Zahlungs-Checkliste": "Payment Checklist",
  "Markierte Anomalien": "Flagged Anomalies",
  "Preiserhöhung erkannt": "Price increase detected",
  "Keine Auffälligkeiten": "No anomalies",
  "Keine ungewöhnlichen Preiserhöhungen in diesem Monat erkannt.":
    "No unusual price increases detected this month.",
  Statistiken: "Statistics",
  "Ausgaben/Tag": "Expenses/day",
  "Importiere Bankdaten um den Rückblick zu sehen": "Import bank data to see the review",

  // Recurring
  Wöchentlich: "Weekly",
  Monatlich: "Monthly",
  Vierteljährlich: "Quarterly",
  Jährlich: "Yearly",
  Heute: "Today",
  Morgen: "Tomorrow",
  "Monatliche Fixkosten": "Monthly Fixed Costs",
  Preisänderungen: "Price Changes",
  Abonnements: "Subscriptions",
  "Erkennung...": "Detecting...",
  Erkennen: "Detect",
  "Importiere zuerst Transaktionen, um wiederkehrende Zahlungen erkennen zu können.":
    "Import transactions first to detect recurring payments.",
  "Keine Muster gefunden": "No patterns found",
  "Die Erkennung hat keine wiederkehrenden Zahlungen in deinen Transaktionen gefunden. Mehr Daten über mehrere Monate verbessern die Erkennung.":
    "Detection found no recurring payments in your transactions. More data over several months improves detection.",
  "Muster erkennen": "Detect Patterns",
  "Analysiere deine Transaktionen, um Abos und regelmäßige Zahlungen automatisch zu finden.":
    "Analyze your transactions to automatically find subscriptions and regular payments.",
  Kalender: "Calendar",
  Zahlung: "Payment",
  Zahlungen: "Payments",
  "12-Monats-Übersicht": "12-Month Overview",

  // Tax
  Werbung: "Work Expenses",
  Gesamt: "Total",
  TAGE: "DAYS",

  // Changelog
  "Was ist neu?": "What's new?",
  "Fehler beim Laden": "Error loading",

  // Onboarding
  "Deine Finanzen, auf deinem Gerät": "Your finances, on your device",
  "Keine Cloud, kein Konto. Deine Daten bleiben auf deinem Gerät — lokal, privat, offline.":
    "No cloud, no account. Your data stays on your device — local, private, offline.",
  "Importiere deine Bankdaten": "Import your bank data",
  "Lade eine CSV-Datei von Comdirect, Trade Republic oder Scalable Capital hoch.":
    "Upload a CSV file from Comdirect, Trade Republic or Scalable Capital.",
  "Wiederkehrend erkennen": "Detect Recurring Payments",
  "Erkenne Abos und Fixkosten automatisch. Sieh, was monatlich fällig wird.":
    "Automatically detect subscriptions and fixed costs. See what's due each month.",
  "Geräte synchronisieren": "Sync Devices",
  "Synchronisiere optional zwischen Geräten — Ende-zu-Ende verschlüsselt.":
    "Optionally sync between devices — end-to-end encrypted.",
  Überspringen: "Skip",
  Weiter: "Next",
  "Los geht's": "Get Started",

  // InfoTooltip
  "Mehr Infos": "More info",
  "Einnahmen minus Ausgaben in diesem Monat. Was dir zum Sparen oder Investieren bleibt.":
    "Income minus expenses this month. What you have left for saving or investing.",
  "Prozent deines Einkommens, das du sparst: (Einnahmen − Ausgaben) ÷ Einnahmen × 100. Ab 20 % gilt als gut.":
    "Percent of your income you save: (income − expenses) ÷ income × 100. ≥20% is considered good.",
  "Kumulatives Nettovermögen über die Zeit, berechnet aus monatlichen Snapshots (Einnahmen − Ausgaben). Mindestens 2 Snapshots erforderlich.":
    "Cumulative net worth over time, calculated from monthly snapshots (income − expenses). Requires at least 2 snapshots.",
  "Deine monatlichen Ausgaben als Farbgitter — inspiriert vom GitHub Contribution Graph. Dunklere Farben bedeuten höhere Ausgaben.":
    "Your monthly expenses as a colored grid — inspired by the GitHub contribution graph. Darker colors mean higher spending.",
  "Summe aller erkannten monatlichen Abos und Fixkosten. Quartals- und Jahresbeiträge werden nicht eingerechnet.":
    "Sum of all detected monthly subscriptions and fixed costs. Quarterly and annual bills are excluded.",
  "Scannt deine Transaktionen nach wiederkehrenden Mustern (mind. 3 ähnliche Beträge in regelmäßigen Abständen). Erkennt Abos, Mieten und Fixkosten.":
    "Scans your transactions for recurring patterns (at least 3 similar amounts at regular intervals). Detects subscriptions, rent, and fixed costs.",
  "Wenn ein erkanntes Abo seinen Preis ändert, erscheint hier eine Warnung mit altem und neuem Betrag. So bemerkst du schleichende Preiserhöhungen frühzeitig.":
    "When a detected subscription changes price, a warning appears here with old and new amount. Helps you spot creeping price hikes early.",

  // Heatmap
  "Ausgaben-Heatmap": "Spending Heatmap",
  "Monatliche Ausgaben im Zeitverlauf": "Monthly expenses over time",
  Wenig: "Low",
  Viel: "High",

  // Net Worth
  Vermögen: "Net Worth",
  Höchster: "Highest",
  Niedrigster: "Lowest",
  Durchschnitt: "Average",

  // Update Banner
  "Neue Version verfügbar": "New version available",
  "Änderungen auf GitHub ansehen": "View changes on GitHub",
  "Diese Version enthält Datenbank-Änderungen. Lokale Daten müssen zurückgesetzt werden.":
    "This version contains database changes. Local data must be reset.",
  "Daten löschen & aktualisieren": "Delete data & update",
  "Jetzt aktualisieren": "Update now",
  Später: "Later",
  "Aktualisiere...": "Updating...",

  // About — FAQ answers (long)
  "Ja. Alle Finanzdaten werden lokal in einer SQLite-Datenbank auf deinem Gerät gespeichert. Sync ist Ende-zu-Ende verschlüsselt — der Server sieht nur Chiffretext.":
    "Yes. All financial data is stored locally in a SQLite database on your device. Sync is end-to-end encrypted — the server only sees ciphertext.",
  "CSV-Import von Comdirect, Trade Republic und Scalable Capital. Da wimg Open-Source ist, können weitere Formate jederzeit hinzugefügt werden.":
    "CSV import from Comdirect, Trade Republic and Scalable Capital. Since wimg is open-source, more formats can be added at any time.",
  "wimg nutzt ein Regel-System mit Schlüsselwörtern. Bekannte Händler (REWE, LIDL, etc.) werden automatisch erkannt. Wenn du eine Transaktion manuell kategorisierst, lernt wimg das Muster und wendet es zukünftig automatisch an. Für den Rest hilft Claude per MCP.":
    "wimg uses a rule system with keywords. Known merchants (REWE, LIDL, etc.) are detected automatically. When you manually categorize a transaction, wimg learns the pattern and applies it automatically in the future. Claude via MCP handles the rest.",
  "Im Browser: OPFS (Origin Private File System). Auf iOS: lokale SQLite-Datei. Deine Daten verlassen dein Gerät nur bei aktivierter Sync — dann Ende-zu-Ende verschlüsselt.":
    "In the browser: OPFS (Origin Private File System). On iOS: local SQLite file. Your data only leaves your device with sync enabled — then end-to-end encrypted.",
  "Ja! Im Dev-Modus oder mit ?devtools in der URL kannst du mit Ctrl+Shift+D ein DevTools-Panel öffnen. Es zeigt WASM-Performance, Speicherverbrauch, Sync-Status, SQL-Abfragen, localStorage und mehr — inspiriert von TanStack DevTools.":
    "Yes! In dev mode or with ?devtools in the URL, you can open a DevTools panel with Ctrl+Shift+D. It shows WASM performance, memory usage, sync status, SQL queries, localStorage and more — inspired by TanStack DevTools.",
  "Gehe zu Einstellungen → Sync aktivieren. Dadurch wird ein einzigartiger Sync-Schlüssel erstellt. Kopiere diesen Schlüssel und füge ihn auf dem zweiten Gerät ein (Einstellungen → Gerät verknüpfen). Änderungen werden in Echtzeit per WebSocket synchronisiert — Ende-zu-Ende verschlüsselt. Ohne Sync funktioniert alles lokal weiter.":
    "Go to Settings → Enable Sync. This creates a unique sync key. Copy this key and paste it on the second device (Settings → Link Device). Changes are synced in real-time via WebSocket — end-to-end encrypted. Without sync, everything continues to work locally.",
  "Ja, vollständig. wimg ist eine PWA (Progressive Web App) und kann über den Browser installiert werden. Alle Daten liegen lokal in SQLite (OPFS). Du brauchst kein Internet für Import, Kategorisierung, Analyse oder irgendeine Kernfunktion. Sync ist optional und funktioniert nur bei Internetverbindung.":
    "Yes, fully. wimg is a PWA (Progressive Web App) and can be installed via the browser. All data is stored locally in SQLite (OPFS). You don't need internet for import, categorization, analysis or any core feature. Sync is optional and only works with an internet connection.",
  "Ja. Über den Konto-Switcher oben rechts kannst du zwischen Konten wechseln oder alle anzeigen. Neue Konten werden beim CSV-Import automatisch erstellt oder können manuell in den Einstellungen angelegt werden. Dashboard, Transaktionen und Analyse filtern automatisch nach dem gewählten Konto.":
    "Yes. Via the account switcher in the top right, you can switch between accounts or show all. New accounts are created automatically during CSV import or can be added manually in settings. Dashboard, transactions and analysis automatically filter by the selected account.",
  "wimg analysiert deine Transaktionen automatisch und erkennt regelmäßige Muster (monatlich, vierteljährlich, jährlich). Unter Mehr → Wiederkehrend siehst du alle erkannten Abos mit Betrag, Intervall und dem nächsten Fälligkeitsdatum. Preisänderungen werden ebenfalls erkannt. Im Kalender-Tab siehst du eine 12-Monats-Vorschau aller anstehenden Zahlungen mit Gesamtbeträgen pro Monat.":
    "wimg automatically analyzes your transactions and detects recurring patterns (monthly, quarterly, yearly). Under More → Recurring you can see all detected subscriptions with amount, interval and next due date. Price changes are also detected. The Calendar tab shows a 12-month preview of all upcoming payments with monthly totals.",
  "Besuche das GitHub-Repository. Code, Übersetzungen, Feedback und Bug-Reports sind willkommen.":
    "Visit the GitHub repository. Code, translations, feedback and bug reports are welcome.",

  // About — FAQ questions missing
  "Welche Banken werden unterstützt?": "Which banks are supported?",
  "Wie synchronisiere ich zwischen Geräten?": "How do I sync between devices?",
  "Kann ich Änderungen rückgängig machen?": "Can I undo changes?",
  "Wie lösche ich meine Daten?": "How do I delete my data?",

  // About — misc
  "Persönliche Finanzverwaltung.": "Personal Finance.",
  "auf deinem Gerät.": "on your device.",
  "PII wird automatisch aus MCP-Antworten entfernt":
    "PII is automatically removed from MCP responses",
  "Personenbezogene Daten (IBANs, Kartennummern, Namen) werden automatisch entfernt.":
    "Personal data (IBANs, card numbers, names) is automatically removed.",
  "Wenn du wimg mit einem MCP-Client verbindest, werden deine Finanzdaten an diesen Client weitergegeben.":
    "When you connect wimg to an MCP client, your financial data is shared with that client.",
  "Mit aktivierter Sync kannst du KI-Assistenten (Claude, etc.) per MCP-Protokoll Zugriff auf deine Finanzdaten geben.":
    "With sync enabled, you can give AI assistants (Claude, etc.) access to your financial data via MCP protocol.",

  // FAQ questions
  "Sind meine Daten sicher?": "Is my data safe?",
  "Wie funktioniert der Import?": "How does import work?",
  "Wie funktioniert die Kategorisierung?": "How does categorization work?",
  "Ist wimg wirklich kostenlos?": "Is wimg really free?",
  "Wo werden die Daten gespeichert?": "Where is data stored?",
  "Was ist der MCP-Server?": "What is the MCP server?",
  "Gibt es Entwickler-Tools?": "Are there developer tools?",
  "Wie funktioniert Auto-Learn?": "How does Auto-Learn work?",
  "Wie erkennt wimg Abos und wiederkehrende Zahlungen?": "How does wimg detect subscriptions?",
  "Funktioniert wimg offline?": "Does wimg work offline?",
  "Gibt es einen Dark Mode?": "Is there a dark mode?",
  "Kann ich mehrere Konten verwalten?": "Can I manage multiple accounts?",
  "Wie kann ich beitragen?": "How can I contribute?",
  "Ja. wimg ist ein Leidenschaftsprojekt unter Open-Source-Lizenz. Keine Abonnements, keine versteckten Kosten, kein Verkauf deiner Daten.":
    "Yes. wimg is a passion project under open-source license. No subscriptions, no hidden costs, no selling your data.",
  "Lade deinen Kontoauszug im CSV-Format hoch. wimg erkennt das Format automatisch, analysiert die Transaktionen lokal und kategorisiert sie mit intelligenten Regeln.":
    "Upload your bank statement in CSV format. wimg detects the format automatically, analyzes transactions locally and categorizes them with smart rules.",

  // Settings feature descriptions

  // Landing / About misc
  "Deine Finanzen,": "Your finances,",
  "Lokal. Privat. Offen.": "Local. Private. Open.",
  "Language / Sprache": "Language / Sprache",
  Transaktionen: "Transactions",

  // Category names (from WASM/Zig — not in .svelte files, pipe through i18n.$ manually)
  Unkategorisiert: "Uncategorized",
  Lebensmittel: "Groceries",
  "Essen gehen": "Dining",
  Transport: "Transport",
  Wohnen: "Housing",
  Nebenkosten: "Utilities",
  Unterhaltung: "Entertainment",
  Shopping: "Shopping",
  Gesundheit: "Health",
  Versicherung: "Insurance",
  Einkommen: "Income",
  Überweisung: "Transfer",
  Bargeld: "Cash",
  Abos: "Subscriptions",
  Reisen: "Travel",
  Bildung: "Education",

  // Goals
  "T überfällig": "d overdue",
  Tagen: "days",
  Mär: "Mar",
  März: "March",
  löschen: "delete",
  "Zuletzt:": "Last:",
  "erkannte Muster": "detected patterns",
  "Dein Sparziel wurde erreicht. Super Leistung!": "You reached your savings goal. Great job!",
  "Diesen Monat hast du mehr ausgegeben als eingenommen.":
    "This month you spent more than you earned.",
  "Einnahmen und Ausgaben waren diesen Monat ausgeglichen.":
    "Income and expenses were balanced this month.",

  // Debts detail strings
  "Aktuell:": "Current:",
  "Vormonat:": "Last month:",
  "-Kosten sind um": " costs increased by",
  "gestiegen (": "(",
  "% mehr).": "% more).",
  "% vs. Vorjahr": "% vs. last year",
  "% vs. Vormonat": "% vs. last month",
  "% vs.": "% vs.",
  von: "of",

  // Tax category labels (from $lib/tax.ts)

  // Command Palette — action groups
  Hilfe: "Help",
  Navigation: "Navigation",
  Konto: "Account",
  Daten: "Data",
  Bearbeiten: "Edit",

  // Command Palette — action labels
  "Auto-Kategorisieren": "Auto-Categorize",
  "Wiederkehrende erkennen": "Detect recurring",
  "CSV exportieren": "Export CSV",
  "Datenbank exportieren": "Export database",
  "Snapshot erstellen": "Create snapshot",
  "Snapshots für alle Monate erstellen": "Create snapshots for all months",
  "Sync-Key kopieren": "Copy Sync Key",
  "Sync trennen": "Disconnect Sync",
  Wiederherstellen: "Restore",
  "Vorheriger Monat": "Previous month",
  "Nächster Monat": "Next month",
  "Design wechseln": "Switch theme",
  "App aktualisieren": "Update app",
  "DevTools öffnen": "Open DevTools",
  "SQL ausführen": "Run SQL",
  "Datenbank löschen": "Delete database",
  "Vollständiger Reset": "Full reset",
  "Sprache wechseln": "Switch language",
  "MCP-Verbindung einrichten": "Set up MCP connection",
  "Wie erkennt wimg Abos?": "How does wimg detect subscriptions?",

  // Toast messages (from actions.svelte.ts)
  "Alle Konten ausgewählt": "All accounts selected",
  "Konto:": "Account:",
  "Transaktionen kategorisiert": "transactions categorized",
  "Keine neuen Kategorien": "No new categories",
  "Muster erkannt": "patterns detected",
  "Keine neuen Muster": "No new patterns",
  "CSV exportiert": "CSV exported",
  "Backup exportiert": "Backup exported",
  "Snapshot erstellt": "Snapshot created",
  "Keine Transaktionen vorhanden": "No transactions available",
  "Snapshots erstellt": "snapshots created",
  "Sync aktiviert": "Sync enabled",
  "Kein gültiger Sync-Key in der Zwischenablage": "No valid sync key in clipboard",
  "Gerät verknüpft — Sync aktiv": "Device linked — Sync active",
  "Zwischenablage konnte nicht gelesen werden": "Could not read clipboard",
  "hoch,": "up,",
  runter: "down",
  "Sync-Key kopiert": "Sync key copied",
  "Sync getrennt": "Sync disconnected",
  "Rückgängig:": "Undo:",
  "Wiederhergestellt:": "Restored:",
  Ein: "On",
  Aus: "Off",
  "Design:": "Theme:",
  Hell: "Light",
  Dunkel: "Dark",
  "Sprache:": "Language:",
  "Fehler:": "Error:",
  "Kategorie:": "Category:",

  // FAQ answers with quotes/unicode (keys must match runtime values)
  'Ja! Über die Command Palette (Cmd+K → "Design wechseln") kannst du zwischen Hell, Dunkel und System wählen. Der Dark Mode hat ein Premium-Design mit dunklem Hintergrund und dezenten Akzenten. Die Einstellung wird gespeichert und beim nächsten Start automatisch angewendet.':
    'Yes! Via the Command Palette (Cmd+K → "Switch theme") you can choose between Light, Dark and System. The dark mode has a premium design with dark background and subtle accents. The setting is saved and automatically applied on next launch.',
  'Unter Einstellungen → Danger Zone kannst du die Datenbank zurücksetzen. Über die Command Palette findest du auch "Datenbank löschen" (löscht nur die SQLite-Datei) und "Vollständiger Reset" (löscht Datenbank, Sync-Schlüssel und alle Einstellungen). Diese Aktionen können nicht rückgängig gemacht werden.':
    'Under Settings → Danger Zone you can reset the database. Via the Command Palette you can also find "Delete database" (deletes only the SQLite file) and "Full reset" (deletes database, sync key and all settings). These actions cannot be undone.',
  'Wenn du eine Transaktion manuell kategorisierst, lernt wimg automatisch das Schlüsselwort (z.B. "REWE" → Lebensmittel). Beim nächsten Import oder Auto-Kategorisieren werden ähnliche Transaktionen automatisch zugeordnet. Alle gelernten Regeln findest du unter Einstellungen → Regeln, wo du sie auch einzeln löschen kannst.':
    'When you manually categorize a transaction, wimg automatically learns the keyword (e.g. "REWE" → Groceries). On the next import or auto-categorize, similar transactions are automatically assigned. All learned rules can be found under Settings → Rules, where you can also delete them individually.',
  Ausführen: "Execute",

  // Photo TAN
  "Bank-Verbindung": "Bank Connection",
  "Warte auf Freigabe": "Waiting for approval",
  "TAN eingeben": "Enter TAN",
  "Warte auf Bank": "Waiting for bank",
  "TAN bestätigen": "Confirm TAN",

  // Toast / Undo
  Rückgängig: "Undo",

  // Account Switcher
  "Alle Konten": "All Accounts",
  "Konto löschen?": "Delete account?",
  "Konto bearbeiten": "Edit account",
  "Kontoname...": "Account name...",
  "Konto hinzufügen": "Add Account",

  // Command Palette
  "Letzte Suchen": "Recent Searches",
  Aktionen: "Actions",
  "Suche oder frage etwas...": "Search or ask something...",
  "Suche leeren": "Clear search",
  "Diese Aktion kann nicht rückgängig gemacht werden.": "This action cannot be undone.",
  "Ja, ausführen": "Yes, proceed",
  "Kategorie ändern": "Change category",
  Ausgeblendet: "Hidden",
  Eingeblendet: "Visible",
  Einblenden: "Show",
  Ausblenden: "Hide",
  Leeren: "Clear",

  // Global
  "CSV hier ablegen": "Drop CSV here",

  // Landing page
  "Lokale Finanzverwaltung. Keine Cloud, kein Konto, kein Tracking. Nur deine Bankdaten in deinem Browser.":
    "Local finance management. No cloud, no account, no tracking. Just your bank data in your browser.",
  "CSV-Import": "CSV Import",
  "Bank-CSV hochladen und Transaktionen sofort sehen. Unterstützt Comdirect, Trade Republic und Scalable Capital.":
    "Upload bank CSV and see transactions instantly. Supports Comdirect, Trade Republic and Scalable Capital.",
  "Auto-Kategorisierung": "Auto-Categorization",
  "Eingebaute Regeln sortieren deine Ausgaben. Optionale KI übernimmt den Rest. Kein manuelles Taggen.":
    "Built-in rules sort your expenses. Optional AI handles the rest. No manual tagging.",
  "Multi-Konto": "Multi-Account",
  "Giro-, Spar- und Anlagekonten an einem Ort. Filtern oder alles zusammen anzeigen.":
    "Checking, savings and investment accounts in one place. Filter or view all together.",
  "wimg ausprobieren": "Try wimg",

  // Mobile apps section
  "Mobile Apps": "Mobile Apps",
  "iOS (TestFlight)": "iOS (TestFlight)",
  "Native SwiftUI-App. Teste die Beta via TestFlight.":
    "Native SwiftUI app. Test the beta via TestFlight.",
  "TestFlight beitreten": "Join TestFlight",
  "Android (APK)": "Android (APK)",
  "Native Kotlin-App. APK herunterladen und installieren.":
    "Native Kotlin app. Download and install the APK.",
  "APK herunterladen": "Download APK",

  // About page
  Privatsphäre: "Privacy",
  "Keine Werbung. Kein Tracking. Niemals.": "No ads. No tracking. Ever.",
  "Quellcode offen auf GitHub verfügbar.": "Source code openly available on GitHub.",
  "Datenschutz im Detail": "Privacy in Detail",
  "Lokal gespeichert": "Stored Locally",
  "SQLite-Datenbank auf deinem Gerät. Kein Cloud-Konto nötig.":
    "SQLite database on your device. No cloud account needed.",
  "Ende-zu-Ende verschlüsselt": "End-to-End Encrypted",
  "Sync nutzt XChaCha20-Poly1305. Der Server sieht nur Chiffretext.":
    "Sync uses XChaCha20-Poly1305. The server only sees ciphertext.",
  "FinTS direkt zur Bank": "FinTS Direct to Bank",
  "Kein Drittanbieter zwischen dir und deiner Bank.": "No third party between you and your bank.",
  "Kein Tracking": "No Tracking",
  "Keine Analytics, kein Sentry, kein Google. Null Telemetrie.":
    "No analytics, no Sentry, no Google. Zero telemetry.",
  "Kein Account": "No Account",
  "Kein Passwort, keine E-Mail. Dein Sync-Schlüssel ist deine Identität.":
    "No password, no email. Your sync key is your identity.",
  "KI sieht keine Klarnamen": "AI Sees No Real Names",
  "MCP-Antworten werden von IBANs, BICs und Namen bereinigt.":
    "MCP responses are stripped of IBANs, BICs and names.",
  "Auf GitHub ansehen": "View on GitHub",
  "MCP-Verbindung": "MCP Connection",
  "Unter Einstellungen einen Sync-Schlüssel erstellen.": "Create a sync key under Settings.",
  'Frage Claude z.B. „Zeig mir meine Ausgaben diesen Monat" oder „Kategorisiere meine letzten Transaktionen".':
    'Ask Claude e.g. "Show me my spending this month" or "Categorize my recent transactions".',
  "MCP-Client konfigurieren": "Configure MCP Client",
  Nutzen: "Use",
  "Datenschutz-Hinweis": "Privacy Notice",
  Datenschutz: "Privacy",
  "Häufig gestellte Fragen": "Frequently Asked Questions",

  // iOS-only: FinTS (flows to .xcstrings, not used on web)
  Bankkonto: "Bank Account",
  "Bank verbinden": "Connect Bank",
  "Kontoauszüge direkt per FinTS abrufen": "Fetch statements directly via FinTS",
  "Bank suchen...": "Search bank...",
  "Lade Banken...": "Loading banks...",
  "Suche eingeben, um alle Banken zu sehen": "Enter search to see all banks",
  Anmeldung: "Login",
  Kennung: "Username",
  "Benutzername / Anmeldekennung": "Username / Login ID",
  "Online-Banking PIN": "Online Banking PIN",
  "Bitte PIN sorgfältig eingeben": "Please enter PIN carefully",
  "Mehrere fehlgeschlagene Anmeldungen können dein Konto bei der Bank sperren. Die PIN wird nicht gespeichert.":
    "Multiple failed login attempts can lock your bank account. The PIN is not stored.",
  Verbinden: "Connect",
  "Andere Bank wählen": "Choose another bank",
  "TAN-Medium wählen": "Choose TAN Medium",
  "Ihre Bank unterstützt mehrere TAN-Verfahren. Bitte wählen Sie das gewünschte Medium.":
    "Your bank supports multiple TAN methods. Please choose the desired medium.",
  "Lade TAN-Medien...": "Loading TAN media...",
  Inaktiv: "Inactive",
  "Weiter ohne Auswahl": "Continue without selection",
  "Freigabe in Banking-App": "Approval in Banking App",
  "TAN-Eingabe": "Enter TAN",
  "Normale Ansicht": "Normal View",
  "Invertierte Ansicht": "Inverted View",
  "Scannen Sie dieses Bild mit Ihrer photoTAN-App": "Scan this image with your photoTAN app",
  "Bitte in Ihrer Banking-App bestätigen.": "Please confirm in your Banking app.",
  "wimg prüft den Status automatisch. Falls nötig, können Sie manuell erneut prüfen.":
    "wimg checks the status automatically. If needed, you can manually re-check.",
  "Status prüfen": "Check Status",
  "TAN senden": "Send TAN",
  "Zeitraum wählen": "Choose Period",
  "Kontoauszüge abrufen": "Fetch Statements",
  "Lade Kontoauszüge...": "Loading statements...",
  "Abruf erfolgreich!": "Fetch successful!",
  Importiert: "Imported",
  Duplikate: "Duplicates",
  "Weitere Bank verbinden": "Connect another bank",
  Kategorisieren: "Categorize",
  "Transaktionen ansehen": "View Transactions",
  "Verbindung fehlgeschlagen": "Connection failed",
  "TAN erforderlich": "TAN required",
  "Letzter Umsatz": "Last transaction",
  "Erstmaliger Abruf – 12 Monate Historie": "First fetch – 12 months of history",
  "PIN nicht gespeichert. Bitte erneut anmelden.": "PIN not saved. Please sign in again.",
  "Anmeldung fehlgeschlagen": "Sign-in failed",
  "3 Monate": "3 months",
  "6 Monate": "6 months",
  "1 Jahr": "1 year",
  "2 Jahre": "2 years",
  "Kategorisiere...": "Categorizing...",
  kategorisiert: "categorized",
  "Abruf fehlgeschlagen": "Fetch failed",

  // iOS-only: all remaining view strings
  Übersicht: "Overview",
  "Letzte Umsätze": "Recent Transactions",
  "Keine Umsätze": "No transactions",
  "Keine Daten für diesen Monat.": "No data for this month.",
  "Alle Filter zurücksetzen": "Reset all filters",
  Auswählen: "Select",
  "Erweiterte Suche": "Advanced Search",
  "Transaktionen suchen...": "Search transactions...",
  "Suchen...": "Search...",
  "Kategorie geändert": "Category changed",
  Kategorisiert: "Categorized",
  "Lade Transaktionen...": "Loading transactions...",
  "Keine Ausgaben": "No expenses",
  Erstellen: "Create",
  Sichern: "Save",
  Farbe: "Color",
  "Datum zurücksetzen": "Reset date",
  "Keyword-Regeln anwenden": "Apply keyword rules",
  "Regel-Engine": "Rule Engine",
  "CSV-Datei importieren": "Import CSV file",
  "Import erfolgreich!": "Import successful!",
  Bankverbindung: "Bank Connection",
  Starten: "Start",
  "Konto löschen": "Delete account",
  "Keine Muster erkannt": "No patterns detected",
  "Keine ungewöhnlichen Preiserhöhungen erkannt.": "No unusual price increases detected.",
  "Importiere Transaktionen und tippe auf Erkennen": "Import transactions and tap Detect",
  "Snapshots für alle Monate": "Snapshots for all months",
  Jahr: "Year",
  Monat: "Month",
  Tage: "Days",
  Name: "Name",
  "Dein Sparziel wurde erreicht. Super!": "You reached your savings goal. Great!",
  "Einnahmen und Ausgaben waren ausgeglichen.": "Income and expenses were balanced.",
  "Privatsphäre zuerst": "Privacy first",
  Über: "About",
  "Version & Links": "Version & Links",
  Version: "Version",
  Fehler: "Error",
  "Zugriff auf die Datei nicht möglich.": "Cannot access the file.",
  "Hell, Dunkel oder System": "Light, Dark or System",
  "Sync aktiviert & Daten hochgeladen": "Sync enabled & data uploaded",
  "Ein Open-Source-Projekt von **Komiljon Maksudov**. Gebaut mit **Zig**, **SwiftUI** und **SQLite**.":
    "An open-source project by **Komiljon Maksudov**. Built with **Zig**, **SwiftUI** and **SQLite**.",
  "Gehe zu Einstellungen → Sync aktivieren. Dadurch wird ein einzigartiger Sync-Schlüssel erstellt. Kopiere diesen Schlüssel und füge ihn auf dem zweiten Gerät ein. Änderungen werden in Echtzeit per WebSocket synchronisiert — Ende-zu-Ende verschlüsselt.":
    "Go to Settings → Enable Sync. This creates a unique sync key. Copy this key and paste it on the second device. Changes are synced in real-time via WebSocket — end-to-end encrypted.",
  "Ja, vollständig. Alle Daten liegen lokal in SQLite. Du brauchst kein Internet für Import, Kategorisierung, Analyse oder irgendeine Kernfunktion. Sync ist optional und funktioniert nur bei Internetverbindung.":
    "Yes, fully. All data is stored locally in SQLite. You don't need internet for import, categorization, analysis or any core feature. Sync is optional and only works with an internet connection.",
  "Ja. Über den Konto-Switcher oben rechts kannst du zwischen Konten wechseln oder alle anzeigen. Neue Konten werden beim CSV-Import automatisch erstellt oder können manuell in den Einstellungen angelegt werden.":
    "Yes. Via the account switcher in the top right, you can switch between accounts or show all. New accounts are created automatically during CSV import or can be added manually in settings.",
  "Unter Einstellungen → Danger Zone kannst du die Datenbank zurücksetzen. Diese Aktion kann nicht rückgängig gemacht werden.":
    "Under Settings → Danger Zone you can reset the database. This action cannot be undone.",
  "Diese TAN-Freigabe erwartet eine scanbare Grafik. Wenn kein Bild angezeigt wird, liefert die Bank ggf. ein nicht direkt darstellbares photoTAN-Format.":
    "This TAN approval expects a scannable graphic. If no image is displayed, the bank may provide a photoTAN format that cannot be displayed directly.",
  "Wenn du wimg mit einem MCP-Client verbindest, werden deine Finanzdaten an diesen Client weitergegeben. Die Daten sind Ende-zu-Ende verschlüsselt zwischen deinen Geräten und dem Server, aber der MCP-Client selbst kann die entschlüsselten Daten lesen. Verwende nur vertrauenswürdige MCP-Clients und teile deinen Sync-Schlüssel niemals mit Dritten.":
    "When you connect wimg to an MCP client, your financial data is shared with that client. Data is end-to-end encrypted between your devices and the server, but the MCP client itself can read the decrypted data. Only use trusted MCP clients and never share your sync key with third parties.",
  "Anmeldung fehlgeschlagen. Bitte überprüfe Kennung und PIN.":
    "Login failed. Please check username and PIN.",
  "Diese Bankleitzahl wird nicht unterstützt.": "This bank routing number is not supported.",
  "In Claude Desktop oder Claude Code die folgende Konfiguration hinzufügen:":
    "Add the following configuration to Claude Desktop or Claude Code:",
  "Comdirect, Trade Republic oder Scalable Capital":
    "Comdirect, Trade Republic or Scalable Capital",

  // Tab bar

  // iOS-only: other views
  "Wähle ein Export-Format": "Choose export format",
  "Backup (JSON)": "Backup (JSON)",

  // App lock (web LockScreen + Settings security card)
  "App-Sperre": "App Lock",
  "App ist gesperrt": "App is locked",
  "Mit PIN und Biometrie geschützt": "Protected with PIN and biometric",
  "Mit PIN geschützt": "Protected with PIN",
  "Mit PIN und optional Biometrie schützen": "Protect with PIN and optional biometric",
  "Neue PIN festlegen (4 Ziffern)": "Set a new PIN (4 digits)",
  "PIN bestätigen": "Confirm PIN",
  "PIN muss 4 Stellen haben.": "PIN must be 4 digits.",
  "PINs stimmen nicht überein.": "PINs do not match.",
  "Biometrie konnte nicht aktiviert werden.": "Could not enable biometric unlock.",
  "PIN einrichten": "Set up PIN",
  "Face ID / Touch ID aktivieren": "Enable Face ID / Touch ID",
  "Biometrie entfernen": "Remove biometric",
  "PIN ändern": "Change PIN",
  "App-Sperre deaktivieren": "Disable app lock",
  "Dieser Browser unterstützt keine biometrische Entsperrung (WebAuthn).":
    "This browser does not support biometric unlock (WebAuthn).",
  "Sperrt wimg mit einer 4-stelligen PIN, optional zusätzlich mit Face ID / Touch ID / Windows Hello via WebAuthn. Beim Tab-Wechsel oder Minimieren wird der Inhalt verschleiert, damit Vorschaubilder im Tab-Switcher deine Daten nicht zeigen. PIN-Hash bleibt lokal im Browser (PBKDF2-SHA256, 100k Iterationen).":
    "Locks wimg with a 4-digit PIN, and optionally also with Face ID / Touch ID / Windows Hello via WebAuthn. When you switch tabs or minimize, the content is blurred so tab-switcher thumbnails don't reveal your data. The PIN hash stays local in the browser (PBKDF2-SHA256, 100k iterations).",
  "Auto-Sperre nach": "Auto-lock after",
  nie: "never",
  "1 Stunde": "1 hour",
  "Zu viele falsche Versuche. Erneut versuchen in": "Too many wrong attempts. Try again in",
  "PIN eingeben": "Enter PIN",
  "PIN zurücksetzen": "Reset PIN",
  "PIN vergessen?": "Forgot PIN?",
  "Zu viele falsche Versuche": "Too many wrong attempts",
  "Mit Face ID / Touch ID entsperren": "Unlock with Face ID / Touch ID",
  "Die PIN lässt sich nicht wiederherstellen. Beim Zurücksetzen werden alle lokalen Daten gelöscht. Falls Sync aktiv war, kannst du deine Daten anschließend mit dem Sync-Schlüssel wiederherstellen.":
    "The PIN cannot be recovered. Resetting deletes all local data. If sync was active, you can restore your data afterwards with your sync key.",

  // FinTS hub redesign
  "Banken & Konten": "Banks & Accounts",
  "Verwalte deine finanziellen Verbindungen sicher an einem Ort.":
    "Manage your financial connections securely in one place.",
  "Verknüpfte Konten": "Linked Accounts",
  "1 Aktiv": "1 Active",
  "PIN fehlt": "PIN missing",
  "Verbinde...": "Connecting...",
  Anmelden: "Sign in",
  "Neues Konto hinzufügen": "Add new account",
  "Häufig gewählt": "Frequently chosen",
  "Alle Banken durchsuchen": "Browse all banks",
  "Keine Bank gefunden": "No bank found",
  "Sicher verknüpft": "Securely linked",
  "FinTS 3.0 — verschlüsselt direkt mit deiner Bank. Login-Daten verlassen dein Gerät nicht.":
    "FinTS 3.0 — encrypted directly with your bank. Login credentials never leave your device.",
  "ENDE-ZU-ENDE VERSCHLÜSSELT": "END-TO-END ENCRYPTED",
  "Anderen Zeitraum wählen": "Choose different period",

  // Background refresh
  "Automatische Bank-Aktualisierung": "Automatic bank refresh",
  "Holt im Hintergrund neue Umsätze": "Fetches new transactions in the background",
  "Erst verfügbar, wenn die PIN für die Schnellabfrage gespeichert ist.":
    "Only available once the quick refresh PIN is saved.",
  "Hintergrund-Aktualisierung": "Background refresh",
  "Neue Umsätze und TAN-Hinweise": "New transactions and TAN prompts",
  "1 neuer Umsatz": "1 new transaction",
  "%d neue Umsätze": "%d new transactions",
  "TAN erforderlich — App öffnen": "TAN required — open the app",
  "Anmeldung abgelaufen — bitte erneut anmelden": "Sign-in expired — please sign in again",
  "Schnellabfrage im Hintergrund": "Background quick refresh",
  "Verbinde zuerst eine Bank und speichere die PIN, um die automatische Aktualisierung zu aktivieren.":
    "Connect a bank and save the PIN first to enable automatic refresh.",
  "iOS weckt die App regelmäßig (meist 1× pro Tag, abhängig von Akku, Netz und Nutzung) und ruft neue Umsätze von deiner Bank ab. Du bekommst eine Mitteilung bei neuen Umsätzen oder wenn eine TAN benötigt wird. Die PIN bleibt im Schlüsselbund deines Geräts. System­weit abschalten unter iOS-Einstellungen → wimg → Hintergrundaktualisierung.":
    "iOS wakes the app periodically (usually once a day, depending on battery, network, and usage) and fetches new transactions from your bank. You get a notification when new transactions are found or a TAN is needed. The PIN stays in your device's Keychain. To disable system-wide go to iOS Settings → wimg → Background App Refresh.",

  // Sync key UI (mask/reveal/QR/link) — keys already in this file are skipped
  // here: "QR-Code anzeigen", "Schließen", "Sync-Schlüssel einfügen".
  "Sync-Schlüssel anzeigen": "Show sync key",
  "Sync-Schlüssel verbergen": "Hide sync key",
  "Sync-Schlüssel kopieren": "Copy sync key",
  "Sync-Schlüssel teilen": "Share sync key",
  "Scanne diesen Code auf deinem anderen Gerät, um es zu verknüpfen.":
    "Scan this code on your other device to link it.",
  Kopieren: "Copy",
  "Nur an deine eigenen Geräte weitergeben — wer den Schlüssel hat, kann auf deine Finanzdaten zugreifen.":
    "Only share with your own devices — anyone with the key can access your financial data.",
  "Mit anderem Gerät verknüpfen": "Link with another device",
  "Füge den Sync-Schlüssel deines anderen Geräts ein. Du findest ihn dort unter Einstellungen → Synchronisierung.":
    "Paste the sync key from your other device. Find it there under Settings → Sync.",
  "Aus Zwischenablage einfügen": "Paste from clipboard",
  "Verknüpfe...": "Linking...",
  "Verknüpft — %d Einträge übernommen": "Linked — %d entries imported",
  "Schon wimg-User? Sync-Schlüssel einfügen": "Already a wimg user? Paste sync key",

  // Credits section
  "Mit Hilfe von": "Built with",
  "Zig & SQLite": "Zig & SQLite",
  "libwimg ist ein Zig-Kern mit eingebetteter SQLite-Amalgamation. Inspiriert von libghostty: Die Bibliothek IS die App.":
    "libwimg is a Zig core with embedded SQLite amalgamation. Inspired by libghostty: the library IS the app.",
  "FinTS-Bankenliste": "FinTS bank catalog",
  "Offizielle Bankenliste von www.fints.org / Die Deutsche Kreditwirtschaft.":
    "Official bank catalog from www.fints.org / Die Deutsche Kreditwirtschaft.",
  "Cloudflare Workers + Durable Objects": "Cloudflare Workers + Durable Objects",
  "Sync-Server, MCP-Endpunkt und Push — alles auf Cloudflares Edge.":
    "Sync server, MCP endpoint, and push — all on Cloudflare's edge.",
  "SwiftUI · SvelteKit · Kotlin Compose": "SwiftUI · SvelteKit · Kotlin Compose",
  "Drei Plattform-Shells über einer Zig-Bibliothek.": "Three platform shells over one Zig library.",
  "python-fints (Raphael Michel)": "python-fints (Raphael Michel)",
  "Open-Source FinTS-3.0-Referenzimplementierung in Python — Wire-Format-Goldstandard für die Zig-Portierung.":
    "Open-source FinTS 3.0 reference implementation in Python — the wire-format gold standard for the Zig port.",
};
