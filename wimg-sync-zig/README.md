# wimg-sync-zig

The wimg sync + MCP server, in Zig, on a Hetzner VPS (`infra/`). Speaks plain
HTTP on `:8080`; Caddy terminates TLS in front (`../infra/wimg-sync.caddy`).
Live at `https://wimg-sync.komiljonmaksudov.com`.

## Endpoints

| Endpoint | What |
| --- | --- |
| `GET /health` | `ok` |
| `POST /sync/:key` | push rows (LWW upsert), broadcast to the key's sockets |
| `GET /sync/:key?since=` | pull rows newer than a timestamp |
| `DELETE /sync/:key` | delete everything stored under a key ("Alle Daten löschen", new key) |
| `GET /ws/:key` | WebSocket: push / pull / changes frames |
| `POST /mcp` | MCP 2026-07-28, stateless, `Authorization: Bearer <sync-key>` |
| `OPTIONS *` | CORS preflight |

Clients pull on open, push on every change (HTTP or WS), and keep a WebSocket
open to get `changes` frames in real time.

### MCP

Links libwimg natively. Per request: derive the encryption key from the Bearer
sync key, load the caller's decrypted rows into an in-memory SQLite, run the
tool, and for a write re-encrypt the changed rows into the store (which also
sends them out over WebSocket). The server only decrypts for MCP requests.

- `query(sql)`: read-only `SELECT`/`WITH` over the wimg schema. Description-like
  columns are scrubbed of IBAN, BIC, card numbers and `EREF+`-style references
  before they leave the server.
- `set_category(transaction_id, category)`: the only write. Takes German,
  English or alias category names and learns a rule for the merchant.

Protocol: **2026-07-28 only**. Every request carries
`params._meta["io.modelcontextprotocol/protocolVersion"]`; no handshake, no
`Mcp-Session-Id`; `server/discover` replaces `initialize`. Results carry
`resultType` + `_meta` serverInfo, lists carry `ttlMs`/`cacheScope`. The
`MCP-Protocol-Version` / `Mcp-Method` / `Mcp-Name` headers must match the body
(`-32020`, HTTP 400). A missing or other version gets `-32022` (HTTP 400)
listing `["2026-07-28"]`; `initialize`/`ping` get `-32601` (404); `GET`/`DELETE`
on `/mcp` get 405.

Claude connector: URL `https://wimg-sync.komiljonmaksudov.com/mcp`, auth
`Bearer <sync-key>`.

## Architecture

```
src/sqlite.zig    minimal SQLite C bindings (links libwimg's vendored sqlite3.c)
src/store.zig     sync_rows, partitioned by sync_key, LWW on updated_at
src/protocol.zig  parse the push body {"rows":[...]}
src/mcp.zig       MCP JSON-RPC: query + set_category via libwimg
src/main.zig      std.Io HTTP + WebSocket server, routing, CORS, per-key registry
```

One OS thread per connection. A mutex-guarded `Registry` tracks the live
WebSockets per sync key; a push fans the rows out to the key's other
connections as a `changes` frame. Each connection has its own write lock, so a
broadcast from another thread can't interleave with its own writes.

All keys share one SQLite file:

```sql
INSERT INTO sync_rows (sync_key, tbl, row_id, data, updated_at) VALUES (...)
ON CONFLICT (sync_key, tbl, row_id) DO UPDATE
SET data = excluded.data, updated_at = excluded.updated_at
WHERE excluded.updated_at > sync_rows.updated_at
```

`data` is the client-encrypted payload, stored as opaque text.

### WebSocket protocol

Client → server: `{type:"push",rows:[...]}`, `{type:"pull",since:N}`, `{type:"pong"}`.
Server → client: `{type:"changes",rows:[...]}`, `{type:"push_ack",merged:N}`,
`{type:"pull_result",rows:[...]}`. A WS push goes to the key's other sockets
(not the sender); an HTTP push goes to all of them (clients ignore their own
echo for 2 s).

## Build & run

```sh
zig build              # → zig-out/bin/wimg-sync
zig build test         # store, protocol, routing and MCP tests
zig build run          # listens on 0.0.0.0:8080, writes ./sync.db
```

Env: `PORT` (default `8080`), `WIMG_SYNC_DB` (default `sync.db`;
`/var/lib/wimg` under systemd), `BIND` (default `0.0.0.0`; the systemd unit sets
`127.0.0.1` so only Caddy reaches it). `make dev` runs it on `:8787`. Uses
`../libwimg/vendor/sqlite3.c` (gitignored; CI fetches it).

## Deploy

From a Mac: `./scripts/deploy-server.sh sync` (repo root). CI never deploys.

## Known gaps

- **MCP write cost**: after a write, `writeBackChanges` reads `wimg_get_changes(0)`
  and re-encrypts every row. Correct (LWW drops the unchanged ones), but wasteful
  for big accounts. A per-key watermark would send only what changed.
- **No server ping**: the server answers client pings but never pings idle
  sockets itself, so a proxy may drop a quiet connection. Clients reconnect on
  close, so nothing breaks.

## Zig notes (0.16+, built with 0.17)

The 0.16 IO redesign moved networking into `std.Io.net` and made `std.Io.Mutex`
need an `Io`. The server uses `std.Io.Threaded` + `std.http.Server`; the store
uses its own atomic spinlock so it doesn't depend on the IO model.
