# wimg Architecture

## Overview

```
libwimg (Zig)
├── sqlite3.c (amalgamation, compiled in — no external dep)
├── src/   root.zig (C ABI), db.zig, parser.zig, categories.zig, recurring.zig,
│          summary.zig, crypto.zig, fints*.zig, mt940.zig, camt.zig, banks.zig
│
├── → libwimg.a         (aarch64-apple-ios, XCFramework)  ← iOS
├── → libwimg.so        (aarch64-linux-android)           ← Android
├── → linked natively                                     ← wimg-sync-zig (MCP)
└── → libwimg-compact.wasm (wasm32-freestanding)          ← wimg-sync Worker (rollback only)

wimg-ios      SwiftUI, links libwimg.a, SQLite file at ~/Documents/wimg.db
wimg-android  Kotlin + Compose, libwimg.so via JNI (wimg_jni.c)
              both: thin shells, UI only, zero business logic

wimg-sync-zig native Zig sync + MCP server, Hetzner VPS behind Caddy
wimg-site     static landing page (wimg.komiljonmaksudov.com)
```

### Data flow

```
User imports a CSV or fetches via FinTS
  → shell passes bytes / JSON to libwimg
  → parser.zig / mt940.zig / camt.zig parse
  → categories.zig assigns categories (keyword rules + learned rules)
  → db.zig writes to SQLite (pending entries go to pending_transactions)
  → root.zig returns length-prefixed JSON
  → shell renders it
```

### Sync

Last-write-wins via `updated_at` on every row. One person, a few devices —
whoever saved last is right. HTTP push/pull + WebSocket broadcast, E2E
encrypted. See `sync.md`.

### FinTS

Native-only (iOS + Android). Protocol in Zig, HTTP via a C callback
(URLSession on iOS, OkHttp on Android). See `fints.md`.
