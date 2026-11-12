<script lang="ts">
  import { afterNavigate } from "$app/navigation";
  import { APP_VERSION, RELEASES_URL } from "$lib/version";

  // Scroll to hash anchor and auto-open <details> after navigation completes.
  // When navigating from the Command Palette, the Drawer locks body scroll
  // with position:fixed — scrollIntoView won't work until the sheet closes and
  // unlocks the body. We poll until the body is unlocked, then scroll.
  afterNavigate(() => {
    const hash = window.location.hash;
    if (!hash) return;
    const id = hash.slice(1);

    function scrollToAnchor() {
      if (document.body.style.position === "fixed") {
        requestAnimationFrame(scrollToAnchor);
        return;
      }
      const el = document.getElementById(id);
      if (!el) return;
      if (el.tagName === "DETAILS") (el as HTMLDetailsElement).open = true;
      el.scrollIntoView({ behavior: "smooth", block: "start" });
    }
    scrollToAnchor();
  });

  // General "how does this work / philosophy" questions. Feature-specific
  // explanations (Sparquote formula, "verfügbar" meaning, 12-Monats-Übersicht)
  // live in inline InfoTooltips on the cards themselves, not here.
  const faqs = [
    {
      id: "faq-sicherheit",
      q: "Sind meine Daten sicher?",
      a: "Ja. Alle Finanzdaten werden lokal in einer SQLite-Datenbank auf deinem Gerät gespeichert. Sync ist Ende-zu-Ende verschlüsselt — der Server sieht nur Chiffretext.",
    },
    {
      id: "faq-banken",
      q: "Welche Banken werden unterstützt?",
      a: "CSV-Import von Comdirect, Trade Republic und Scalable Capital. Da wimg Open-Source ist, können weitere Formate jederzeit hinzugefügt werden.",
    },
    {
      id: "faq-import",
      q: "Wie funktioniert der Import?",
      a: "Lade deinen Kontoauszug im CSV-Format hoch. wimg erkennt das Format automatisch, analysiert die Transaktionen lokal und kategorisiert sie mit intelligenten Regeln.",
    },
    {
      id: "faq-kategorisierung",
      q: "Wie funktioniert die Kategorisierung?",
      a: "wimg nutzt ein Regel-System mit Schlüsselwörtern. Bekannte Händler (REWE, LIDL, etc.) werden automatisch erkannt. Wenn du eine Transaktion manuell kategorisierst, lernt wimg das Muster und wendet es zukünftig automatisch an. Für den Rest hilft Claude per MCP.",
    },
    {
      id: "faq-kostenlos",
      q: "Ist wimg wirklich kostenlos?",
      a: "Ja. wimg ist ein Leidenschaftsprojekt unter Open-Source-Lizenz. Keine Abonnements, keine versteckten Kosten, kein Verkauf deiner Daten.",
    },
    {
      id: "faq-speicherung",
      q: "Wo werden die Daten gespeichert?",
      a: "Im Browser: OPFS (Origin Private File System). Auf iOS: lokale SQLite-Datei. Deine Daten verlassen dein Gerät nur bei aktivierter Sync — dann Ende-zu-Ende verschlüsselt.",
    },
    {
      id: "faq-mcp",
      q: "Was ist der MCP-Server?",
      a: "Mit aktivierter Synchronisierung wird dein Sync-Schlüssel zum MCP-Zugang. Claude.ai oder andere KI-Tools können Ausgaben abfragen und Kategorien setzen — Ende-zu-Ende verschlüsselt, in Echtzeit synchronisiert.",
    },
    {
      id: "faq-devtools",
      q: "Gibt es Entwickler-Tools?",
      a: 'Ja! Im Dev-Modus oder mit ?devtools in der URL kannst du mit Ctrl+Shift+D ein DevTools-Panel öffnen. Es zeigt WASM-Performance, Speicherverbrauch, Sync-Status, SQL-Abfragen, localStorage und mehr — inspiriert von TanStack DevTools.',
    },
    {
      id: "faq-autolearn",
      q: "Wie funktioniert Auto-Learn?",
      a: 'Wenn du eine Transaktion manuell kategorisierst, lernt wimg automatisch das Schlüsselwort (z.B. "REWE" → Lebensmittel). Beim nächsten Import oder Auto-Kategorisieren werden ähnliche Transaktionen automatisch zugeordnet. Alle gelernten Regeln findest du unter Einstellungen → Regeln, wo du sie auch einzeln löschen kannst.',
    },
    {
      id: "faq-sync",
      q: "Wie synchronisiere ich zwischen Geräten?",
      a: "Gehe zu Einstellungen → Sync aktivieren. Dadurch wird ein einzigartiger Sync-Schlüssel erstellt. Kopiere diesen Schlüssel und füge ihn auf dem zweiten Gerät ein (Einstellungen → Gerät verknüpfen). Änderungen werden in Echtzeit per WebSocket synchronisiert — Ende-zu-Ende verschlüsselt. Ohne Sync funktioniert alles lokal weiter.",
    },
    {
      id: "faq-recurring",
      q: "Wie erkennt wimg Abos und wiederkehrende Zahlungen?",
      a: "wimg analysiert deine Transaktionen automatisch und erkennt regelmäßige Muster (monatlich, vierteljährlich, jährlich). Unter Mehr → Wiederkehrend siehst du alle erkannten Abos mit Betrag, Intervall und dem nächsten Fälligkeitsdatum. Preisänderungen werden ebenfalls erkannt. Im Kalender-Tab siehst du eine 12-Monats-Vorschau aller anstehenden Zahlungen mit Gesamtbeträgen pro Monat.",
    },
    {
      id: "faq-offline",
      q: "Funktioniert wimg offline?",
      a: "Ja, vollständig. wimg ist eine PWA (Progressive Web App) und kann über den Browser installiert werden. Alle Daten liegen lokal in SQLite (OPFS). Du brauchst kein Internet für Import, Kategorisierung, Analyse oder irgendeine Kernfunktion. Sync ist optional und funktioniert nur bei Internetverbindung.",
    },
    {
      id: "faq-ios",
      q: "Gibt es eine iOS-App?",
      a: "Ja! wimg gibt es als native SwiftUI-App für iPhone. Tritt der TestFlight-Beta bei unter testflight.apple.com/join/v5FhHpt5. Die iOS-App hat volle Feature-Parität mit der Web-App inklusive FinTS-Bankverbindung, Sync und Dark Mode.",
    },
    {
      id: "faq-android",
      q: "Gibt es eine Android-App?",
      a: "Ja! Die native Kotlin/Compose-App kann als APK von der GitHub Releases-Seite heruntergeladen werden. Unter Einstellungen → Unbekannte Quellen erlauben, dann die APK installieren. Volle Feature-Parität mit iOS und Web.",
    },
    {
      id: "faq-darkmode",
      q: "Gibt es einen Dark Mode?",
      a: 'Ja! Über die Command Palette (Cmd+K → "Design wechseln") kannst du zwischen Hell, Dunkel und System wählen. Der Dark Mode hat ein Premium-Design mit dunklem Hintergrund und dezenten Akzenten. Die Einstellung wird gespeichert und beim nächsten Start automatisch angewendet.',
    },
    {
      id: "faq-multiaccounts",
      q: "Kann ich mehrere Konten verwalten?",
      a: "Ja. Über den Konto-Switcher oben rechts kannst du zwischen Konten wechseln oder alle anzeigen. Neue Konten werden beim CSV-Import automatisch erstellt oder können manuell in den Einstellungen angelegt werden. Dashboard, Transaktionen und Analyse filtern automatisch nach dem gewählten Konto.",
    },
    {
      id: "faq-undo",
      q: "Kann ich Änderungen rückgängig machen?",
      a: 'Ja. Nach jeder Aktion (Kategorisierung, Konto-Änderung etc.) erscheint ein Undo-Toast am unteren Bildschirmrand. Auch über die Command Palette (Cmd+K → "Rückgängig") oder Cmd+Z kannst du die letzte Aktion rückgängig machen. wimg speichert bis zu 50 Undo-Schritte.',
    },
    {
      id: "faq-datenloeschen",
      q: "Wie lösche ich meine Daten?",
      a: 'Unter Einstellungen → Danger Zone kannst du die Datenbank zurücksetzen. Über die Command Palette findest du auch "Datenbank löschen" (löscht nur die SQLite-Datei) und "Vollständiger Reset" (löscht Datenbank, Sync-Schlüssel und alle Einstellungen). Diese Aktionen können nicht rückgängig gemacht werden.',
    },
    {
      id: "faq-beitragen",
      q: "Wie kann ich beitragen?",
      a: "Besuche das GitHub-Repository. Code, Übersetzungen, Feedback und Bug-Reports sind willkommen.",
    },
  ];
</script>

<section class="space-y-5">
  <!-- Header -->
  <div class="flex items-center gap-3">
    <a
      href="/more"
      class="w-10 h-10 rounded-2xl bg-white flex items-center justify-center shadow-sm"
      aria-label="Zurück"
    >
      <svg
        class="w-5 h-5 text-(--color-text)"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M15 19l-7-7 7-7"
        />
      </svg>
    </a>
    <h2 class="text-2xl font-display font-extrabold text-(--color-text)">
      Über wimg
    </h2>
  </div>

  <!-- Hero card -->
  <div
    class="border border-gray-100 rounded-3xl p-6 flex flex-col items-center text-center"
  >
    <div
      class="w-16 h-16 rounded-2xl flex items-center justify-center mb-4"
      style="background: #1a1a1a"
    >
      <svg
        class="w-8 h-8 text-white"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
          d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z"
        />
      </svg>
    </div>
    <h3 class="text-xl font-display font-extrabold text-(--color-text) mb-1">
      wimg
    </h3>
    <p class="text-sm text-(--color-text)/70 font-medium">
      Persönliche Finanzverwaltung.<br />Lokal. Privat. Offen.
    </p>
    <p class="text-xs text-(--color-text)/50 mt-3">
      Von <span class="font-semibold">Komiljon Maksudov</span> &middot; Zig + Svelte
      + SQLite
    </p>
  </div>

  <!-- Quick info grid -->
  <div class="grid grid-cols-2 gap-3">
    <div class="bg-white rounded-2xl p-4 border border-gray-100">
      <div
        class="w-9 h-9 rounded-xl bg-emerald-50 flex items-center justify-center mb-2.5"
      >
        <svg
          class="w-4.5 h-4.5 text-emerald-600"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="1.5"
            d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"
          />
        </svg>
      </div>
      <h4 class="font-bold text-sm text-(--color-text) mb-0.5">Privatsphäre</h4>
      <p class="text-xs text-(--color-text-secondary) leading-snug">
        Keine Werbung. Kein Tracking. Niemals.
      </p>
    </div>
    <div class="bg-white rounded-2xl p-4 border border-gray-100">
      <div
        class="w-9 h-9 rounded-xl bg-purple-50 flex items-center justify-center mb-2.5"
      >
        <svg
          class="w-4.5 h-4.5 text-purple-600"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="1.5"
            d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"
          />
        </svg>
      </div>
      <h4 class="font-bold text-sm text-(--color-text) mb-0.5">Open Source</h4>
      <p class="text-xs text-(--color-text-secondary) leading-snug">
        Quellcode offen auf GitHub verfügbar.
      </p>
    </div>
  </div>

  <!-- Privacy details -->
  <div class="bg-white rounded-2xl p-5 border border-gray-100 space-y-3">
    <h3 class="font-bold text-sm text-(--color-text)">Datenschutz im Detail</h3>
    {#each [
      { icon: "🔒", title: "Lokal gespeichert", desc: "SQLite-Datenbank auf deinem Gerät. Kein Cloud-Konto nötig." },
      { icon: "🔐", title: "Ende-zu-Ende verschlüsselt", desc: "Sync nutzt XChaCha20-Poly1305. Der Server sieht nur Chiffretext." },
      { icon: "🏦", title: "FinTS direkt zur Bank", desc: "Kein Drittanbieter zwischen dir und deiner Bank." },
      { icon: "🚫", title: "Kein Tracking", desc: "Keine Analytics, kein Sentry, kein Google. Null Telemetrie." },
      { icon: "👤", title: "Kein Account", desc: "Kein Passwort, keine E-Mail. Dein Sync-Schlüssel ist deine Identität." },
      { icon: "🧠", title: "KI sieht keine Klarnamen", desc: "MCP-Antworten werden von IBANs, BICs und Namen bereinigt." },
    ] as item (item.title)}
      <div class="flex gap-3 items-start">
        <span class="text-base leading-none mt-0.5">{item.icon}</span>
        <div>
          <p class="text-xs font-semibold text-(--color-text)">{item.title}</p>
          <p class="text-xs text-(--color-text-secondary) leading-snug">{item.desc}</p>
        </div>
      </div>
    {/each}
  </div>

  <!-- GitHub button -->
  <a
    href="https://github.com/milimyname/wimg"
    target="_blank"
    rel="noopener noreferrer"
    class="flex items-center justify-center gap-2.5 w-full py-3.5 bg-(--color-text) text-white font-bold text-sm rounded-2xl hover:opacity-90 transition-opacity active:scale-[0.98]"
  >
    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
      <path
        d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"
      />
    </svg>
    Auf GitHub ansehen
  </a>

  <!-- MCP Connection Guide -->
  <div id="mcp" class="space-y-3">
    <h3
      class="text-lg font-display font-extrabold text-(--color-text) flex items-center gap-2"
    >
      <svg
        class="w-4.5 h-4.5 text-purple-500"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
          d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"
        />
      </svg>
      MCP-Verbindung
    </h3>

    <p class="text-sm text-(--color-text-secondary) leading-relaxed">
      Mit aktivierter Sync kannst du KI-Assistenten (Claude, etc.) per MCP-Protokoll Zugriff auf deine Finanzdaten geben.
    </p>

    <!-- Step 1 -->
    <div class="bg-white rounded-2xl border border-gray-100 p-4 flex items-start gap-3">
      <span class="shrink-0 w-7 h-7 rounded-full bg-(--color-accent) text-(--color-text) flex items-center justify-center text-xs font-bold">1</span>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-semibold text-(--color-text)">Sync aktivieren</p>
        <p class="text-xs text-(--color-text-secondary) leading-snug mt-0.5">
          Unter <a href="/settings" class="font-bold text-(--color-text) underline">Einstellungen</a> einen Sync-Schlüssel erstellen.
        </p>
      </div>
    </div>

    <!-- Step 2 -->
    <div class="bg-white rounded-2xl border border-gray-100 p-4 flex items-start gap-3">
      <span class="shrink-0 w-7 h-7 rounded-full bg-(--color-accent) text-(--color-text) flex items-center justify-center text-xs font-bold">2</span>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-semibold text-(--color-text)">MCP-Client konfigurieren</p>
        <p class="text-xs text-(--color-text-secondary) leading-snug mt-0.5">
          In Claude Desktop oder Claude Code die folgende Konfiguration hinzufügen:
        </p>
      </div>
    </div>

    <!-- JSON config code block -->
    <pre class="bg-gray-50 border border-gray-100 rounded-xl p-3 text-[11px] font-mono text-(--color-text) overflow-x-auto leading-snug whitespace-pre">{`{
  "mcpServers": {
    "wimg": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "https://wimg-sync.komiljonmaksudov.com/mcp",
        "--header",
        "Authorization: Bearer DEIN-SYNC-SCHLÜSSEL"
      ]
    }
  }
}`}</pre>

    <!-- Step 3 -->
    <div class="bg-white rounded-2xl border border-gray-100 p-4 flex items-start gap-3">
      <span class="shrink-0 w-7 h-7 rounded-full bg-(--color-accent) text-(--color-text) flex items-center justify-center text-xs font-bold">3</span>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-semibold text-(--color-text)">Nutzen</p>
        <p class="text-xs text-(--color-text-secondary) leading-snug mt-0.5">
          Frage Claude z.B. „Zeig mir meine Ausgaben diesen Monat" oder „Kategorisiere meine letzten Transaktionen".
        </p>
      </div>
    </div>

    <!-- Privacy warning -->
    <div class="flex items-start gap-3 p-4 rounded-2xl bg-orange-50 border border-orange-100">
      <svg class="w-5 h-5 text-orange-500 shrink-0 mt-0.5" fill="currentColor" viewBox="0 0 20 20">
        <path fill-rule="evenodd" d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 6a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 6zm0 9a1 1 0 100-2 1 1 0 000 2z" clip-rule="evenodd" />
      </svg>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-bold text-orange-700">Datenschutz-Hinweis</p>
        <p class="text-xs text-orange-700/80 leading-snug mt-0.5">
          Wenn du wimg mit einem MCP-Client verbindest, werden deine Finanzdaten an diesen Client weitergegeben. Die Daten sind Ende-zu-Ende verschlüsselt zwischen deinen Geräten und dem Server, aber der MCP-Client selbst kann die entschlüsselten Daten lesen. Verwende nur vertrauenswürdige MCP-Clients und teile deinen Sync-Schlüssel niemals mit Dritten.
        </p>
      </div>
    </div>
  </div>

  <!-- Credits -->
  <div class="space-y-3">
    <h3 class="text-lg font-display font-extrabold text-(--color-text) mb-1 flex items-center gap-2">
      <svg class="w-4.5 h-4.5 text-pink-500" fill="currentColor" viewBox="0 0 24 24">
        <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z" />
      </svg>
      Mit Hilfe von
    </h3>
    <div class="space-y-2 p-4 rounded-2xl bg-(--color-card)">
      <div class="flex gap-3 items-start">
        <svg class="w-4 h-4 text-pink-500 mt-0.5 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4" /></svg>
        <div>
          <div class="text-sm font-bold text-(--color-text)">Zig &amp; SQLite</div>
          <div class="text-xs text-(--color-text-secondary)">
            libwimg ist ein Zig-Kern mit eingebetteter SQLite-Amalgamation. Inspiriert von libghostty: Die Bibliothek IS die App.
          </div>
        </div>
      </div>
      <div class="flex gap-3 items-start">
        <svg class="w-4 h-4 text-pink-500 mt-0.5 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
        <div>
          <div class="text-sm font-bold text-(--color-text)">
            <a href="https://github.com/raphaelm/python-fints" target="_blank" rel="noopener" class="underline decoration-dotted underline-offset-2">python-fints (Raphael Michel)</a>
          </div>
          <div class="text-xs text-(--color-text-secondary)">
            Open-Source FinTS-3.0-Referenzimplementierung in Python — Wire-Format-Goldstandard für die Zig-Portierung.
          </div>
        </div>
      </div>
      <div class="flex gap-3 items-start">
        <svg class="w-4 h-4 text-pink-500 mt-0.5 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" /></svg>
        <div>
          <div class="text-sm font-bold text-(--color-text)">
            <a href="https://www.fints.org/" target="_blank" rel="noopener" class="underline decoration-dotted underline-offset-2">FinTS-Bankenliste</a>
          </div>
          <div class="text-xs text-(--color-text-secondary)">
            Offizielle Bankenliste von www.fints.org / Die Deutsche Kreditwirtschaft.
          </div>
        </div>
      </div>
      <div class="flex gap-3 items-start">
        <svg class="w-4 h-4 text-pink-500 mt-0.5 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3 15a4 4 0 004 4h9a5 5 0 10-.1-9.999 5.002 5.002 0 10-9.78 2.096A4.001 4.001 0 003 15z" /></svg>
        <div>
          <div class="text-sm font-bold text-(--color-text)">Cloudflare Workers + Durable Objects</div>
          <div class="text-xs text-(--color-text-secondary)">
            Sync-Server, MCP-Endpunkt und Push — alles auf Cloudflares Edge.
          </div>
        </div>
      </div>
      <div class="flex gap-3 items-start">
        <svg class="w-4 h-4 text-pink-500 mt-0.5 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M7 4v16M17 4v16M3 8h4m10 0h4M3 12h18M3 16h4m10 0h4M4 20h16a1 1 0 001-1V5a1 1 0 00-1-1H4a1 1 0 00-1 1v14a1 1 0 001 1z" /></svg>
        <div>
          <div class="text-sm font-bold text-(--color-text)">SwiftUI · SvelteKit · Kotlin Compose</div>
          <div class="text-xs text-(--color-text-secondary)">
            Drei Plattform-Shells über einer Zig-Bibliothek.
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- FAQ -->
  <div id="faq">
    <h3
      class="text-lg font-display font-extrabold text-(--color-text) mb-3 flex items-center gap-2"
    >
      <svg
        class="w-4.5 h-4.5 text-amber-500"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
          d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
        />
      </svg>
      Häufig gestellte Fragen
    </h3>

    <div class="space-y-2">
      {#each faqs as faq (faq.id)}
        <details
          id={faq.id}
          class="group bg-white rounded-2xl border border-gray-100 overflow-hidden"
        >
          <summary
            class="flex cursor-pointer items-center justify-between p-4 list-none select-none"
          >
            <span class="font-semibold text-sm text-(--color-text) pr-4"
              >{faq.q}</span
            >
            <svg
              class="w-4 h-4 text-(--color-text-secondary) shrink-0 transition-transform group-open:rotate-180"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 9l-7 7-7-7"
              />
            </svg>
          </summary>
          <div
            class="px-4 pb-4 text-sm text-(--color-text-secondary) leading-relaxed"
          >
            {faq.a}
          </div>
        </details>
      {/each}
    </div>
  </div>

  <!-- Footer -->
  <footer
    class="flex flex-col items-center gap-2 pt-2 pb-6 text-(--color-text-secondary)"
  >
    <a
      href={RELEASES_URL}
      target="_blank"
      rel="noopener noreferrer"
      class="text-xs font-bold text-amber-600 hover:underline"
    >
      Was ist neu?
    </a>
    <span class="text-xs font-mono opacity-50">v{APP_VERSION}</span>
  </footer>
</section>

<style>
  summary::-webkit-details-marker,
  summary::marker {
    display: none;
  }
</style>
