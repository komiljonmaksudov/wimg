# wimg-sync-zig

Native Zig rewrite of the `wimg-sync` Cloudflare Worker — the "Phase 1 binary"
that `infra/` provisions a VPS for. Speaks plain HTTP on `:8080`; Caddy
terminates TLS in front (see `../infra/Caddyfile`).

## Why

`wimg-sync/` (TypeScript on CF Workers + Durable Objects) works, but moving sync
onto a self-hosted Hetzner box aligns with wimg's local-first, no-intermediary
values and removes the Cloudflare dependency. `infra/` already has the
provisioning, systemd units, Caddy config, and restic backups — it was just
waiting for this binary at `zig-out/bin/wimg-sync`.

## Status

| Endpoint | Status |
| --- | --- |
| `GET /health` | ✅ done |
| `POST /sync/:key` (push, LWW upsert) | ✅ done |
| `GET /sync/:key?since=` (pull) | ✅ done |
| CORS preflight (`OPTIONS`) | ✅ done |
| `GET /ws/:key` (real-time WebSocket) | ✅ done |
| `POST /mcp` (MCP 2026-07-28, stateless) | ✅ done (2 tools) |

The HTTP and WebSocket sync paths are **wire-compatible** with the Worker, so no
client changes are needed. Clients pull on open, push on every mutation (HTTP or
WS), and hold a WebSocket open to receive `changes` frames in real time.

### MCP

`POST /mcp` with `Authorization: Bearer <sync-key>` speaks MCP over Streamable
HTTP. It links libwimg directly (no WASM), and per request: derives the
encryption key, loads the caller's decrypted rows into an in-memory SQLite, runs
the tool, and — for writes — re-encrypts the changed rows back into the Store
(which also fans them out over WebSocket). Two tools, matching the Worker:

- `query(sql)` — read-only `SELECT`/`WITH` over the wimg schema.
- `set_category(transaction_id, category)` — the only write; resolves
  German/English/alias category names and auto-learns a rule.

`query` results are PII-scrubbed (IBAN / BIC / card / `EREF+`-style reference
fields) on description-like columns before they leave the server, matching the
Worker's `stripPII`. Code Mode (the Worker's CF-specific sandbox wrapper) is
intentionally dropped — the tools are exposed directly as standard MCP tools.

Protocol: **MCP 2026-07-28 only** (stateless). Every request carries
`params._meta["io.modelcontextprotocol/protocolVersion"]`. No handshake, no
`Mcp-Session-Id`; `server/discover` replaces `initialize`; results carry
`resultType` + `_meta` serverInfo, lists carry `ttlMs`/`cacheScope`. The
`MCP-Protocol-Version` / `Mcp-Method` / `Mcp-Name` headers must mirror the body
(`-32020`, HTTP 400). A request without the version `_meta` (the 2025-03-26
`initialize` flow) or with another version gets `-32022` (HTTP 400) listing
`["2026-07-28"]`; `initialize`/`ping` get `-32601` (404). Only `POST /mcp`
exists — `GET`/`DELETE` answer 405.

## Architecture

```
src/sqlite.zig    minimal SQLite C bindings (links libwimg's vendored sqlite3.c)
src/store.zig     sync_rows store, partitioned by sync_key, LWW on updated_at
src/protocol.zig  parse the push body {"rows":[...]} into rows
src/mcp.zig       MCP JSON-RPC: query + set_category, via libwimg (linked native)
src/main.zig      std.Io HTTP + WebSocket server, routing, CORS, per-key registry
```

Concurrency: one OS thread per connection. A mutex-guarded `Registry` tracks the
live WebSocket connections per sync key; an HTTP push (or a WS push) fans the
incoming rows out to the other connections as a `changes` frame. Each connection
has its own write lock so a broadcast from another thread can't interleave with
the connection's own writes.

The Worker gives each sync key its own Durable Object (its own SQLite). One VPS
process serves every key, so rows are partitioned by a `sync_key` column instead
of by database. The merge SQL is byte-for-byte the Worker's:

```sql
INSERT INTO sync_rows (sync_key, tbl, row_id, data, updated_at) VALUES (...)
ON CONFLICT (sync_key, tbl, row_id) DO UPDATE
SET data = excluded.data, updated_at = excluded.updated_at
WHERE excluded.updated_at > sync_rows.updated_at
```

`data` is the client-side-encrypted payload — the server stores it as opaque
JSON text and never decrypts it for sync (only MCP would, once ported).

## Build & run

```sh
zig build              # → zig-out/bin/wimg-sync
zig build test         # store + protocol + routing unit tests
zig build run          # listens on 0.0.0.0:8080, writes ./sync.db
```

Config via env: `PORT` (default `8080`, matching the Caddyfile), `WIMG_SYNC_DB`
(default `sync.db`, relative to the working dir — `/var/lib/wimg` under systemd),
and `BIND` (default `0.0.0.0`; the systemd unit sets `127.0.0.1` so only Caddy
on the same host can reach it). Local dev: `WIMG_NATIVE_SYNC=1 ./scripts/dev.sh` runs this server
on `:8787` so the web client's dev URL hits it unchanged. Reuses
`../libwimg/vendor/sqlite3.c` rather than vendoring a second 9 MB copy, so the
libwimg amalgamation must be present (it's gitignored; CI fetches it).

## Deploy

```sh
VPS=root@<ip> ../infra/scripts/deploy.sh   # builds nothing — expects zig-out/bin/wimg-sync
```

`deploy.sh` already points at `wimg-sync-zig/zig-out/bin/wimg-sync`.

## Remaining work (Phase 2)

1. **MCP write watermark** — `writeBackChanges` calls `wimg_get_changes(0)`, so a
   write re-encrypts every row (LWW dedups, so it's correct but wasteful). Track a
   per-key watermark to push only what changed.
2. **Server-initiated ping** — the Worker pings every 30 s so idle sockets stay
   alive through proxies. This server replies `pong` to client pings and handles
   `ConnectionClose`, but doesn't ping on its own yet (needs a read timeout or a
   per-connection timer). Clients reconnect on close, so it's not blocking.
3. **Cutover** — DNS, client `config.ts`/iOS/Android base URLs, and CLAUDE.md
   (still documents sync as CF Durable Objects).

### WebSocket protocol (implemented, matches `../wimg-sync/src/sync-room.ts`)

Client → server: `{type:"push",rows:[...]}`, `{type:"pull",since:N}`, `{type:"pong"}`.
Server → client: `{type:"changes",rows:[...]}` (fan-out), `{type:"push_ack",merged:N}`,
`{type:"pull_result",rows:[...]}`. A WS push is broadcast to the key's other
sockets (sender excluded); an HTTP push is broadcast to all of them (clients
suppress their own echo via a 2 s window).

## Notes on Zig 0.16

The 0.16 IO redesign moved networking into `std.Io.net` (the old `std.posix`
socket wrappers are gone) and made `std.Io.Mutex` require an `Io`. The server
uses `std.Io.Threaded` + `std.http.Server`; the store uses a self-contained
atomic spinlock so it stays independent of the IO model.
