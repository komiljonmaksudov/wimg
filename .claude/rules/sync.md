# Sync System

## Overview

Row-level sync using `updated_at` columns, last-write-wins per row, no CRDTs.
Production server: `wimg-sync-zig/` (native Zig, links libwimg) on the Hetzner
VPS behind Caddy (`infra/wimg-sync.caddy`, `infra/systemd/wimg-sync.service`),
at `https://wimg-sync.komiljonmaksudov.com`. Details: `wimg-sync-zig/README.md`.

`wimg-sync/` (Cloudflare Worker + Durable Objects + compact WASM) is a rollback
path only. CI no longer deploys it.

## How it works

1. User taps "Sync aktivieren" → generates a sync key
2. Sync key IS the identity — no signup, no auth
3. Changes pushed via HTTP POST or WS → server merges + broadcasts to the key's other sockets
4. All connected devices receive changes in real-time (~1-2 seconds)

## API

```
GET  /health
POST /sync/:key          — push changed rows (LWW upsert + WS broadcast)
GET  /sync/:key?since=ts — pull rows newer than timestamp
GET  /ws/:key            — WebSocket: push / pull / changes frames
POST /mcp                — MCP 2026-07-28 JSON-RPC, stateless (Bearer: sync-key); no GET/DELETE
```

## E2E Encryption

All data encrypted client-side. Key derived from sync key via HKDF-SHA256
(`wimg_derive_key`), XChaCha20-Poly1305 per field. Sync stores ciphertext only.

## Sync triggers

- Pull on app open
- Push on every local mutation
- Real-time WebSocket broadcast
- Echo suppression (2-second window after push)
- Full sync on linking new device

## Devices, wrong key, new key (board 21, client-side only)

- **Devices**: every device keeps a row in the synced `sync_devices` table
  (name, kind, last seen). Removing one marks it deleted; when that device
  pulls the mark, it stops syncing (its local data stays). No server change.
- **Wrong key**: before linking, the app reads `GET /sync/:key?since=0` without
  saving the key. No rows, or rows the key can't decrypt → "Schlüssel passt
  nicht"; nothing is pushed under a wrong key.
- **New key**: the other devices are marked removed, the server copy under the
  old key is deleted (`DELETE /sync/:key`), only the removal marks are written
  back there so the others learn they are out, and everything is pushed again
  under a fresh key.

## Storage

One SQLite file for all keys: `sync_rows (sync_key, tbl, row_id, data, updated_at)`,
`INSERT ... ON CONFLICT DO UPDATE WHERE excluded.updated_at > sync_rows.updated_at`.
Pending ("Vorgemerkt") transactions are device-only and never synced.

## MCP Server

`wimg-sync-zig/src/mcp.zig`. Per request: derive the key from the Bearer sync
key, load the caller's decrypted rows into libwimg's in-memory SQLite, run the
tool, re-encrypt writes back into the store. Two tools: `query(sql)` (read-only,
PII-scrubbed) and `set_category(transaction_id, category)` (auto-learns a rule).
The server only decrypts for MCP requests.

Claude.ai connector: `URL: https://wimg-sync.komiljonmaksudov.com/mcp`, `Auth: Bearer <sync-key>`
