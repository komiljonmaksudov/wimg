# Sync System

## Overview

Row-level sync using `updated_at` columns. Cloudflare Worker + Durable Objects
with WebSocket Hibernation API. Hono router. Last-write-wins per row. No CRDTs.

## How it works

1. User taps "Sync aktivieren" → generates UUID sync key
2. Sync key IS the identity — no signup, no auth
3. Changes pushed via HTTP POST → DO merges to SQLite + broadcasts via WebSocket
4. All connected devices receive changes in real-time (~1-2 seconds)

## API

```
POST /sync/:key          — push changed rows (HTTP → DO merges + WS broadcast)
GET  /sync/:key?since=ts — pull rows newer than timestamp
GET  /ws/:key            — WebSocket upgrade → real-time sync via DO
POST /mcp                — MCP 2026-07-28 JSON-RPC, stateless (Bearer: sync-key); no GET/DELETE
```

## E2E Encryption

All data encrypted client-side. Key derived from sync key via HKDF-SHA256.
XChaCha20-Poly1305 encrypt/decrypt. Server stores ciphertext only.

## Sync triggers

- Pull on app open
- Push on every local mutation (setOnMutate callback)
- Real-time WebSocket broadcast
- Echo suppression (2-second window after push)
- Full sync on linking new device

## Storage

DO SQLite — each SyncRoom DO has a `sync_rows` table with `(tbl, row_id, data, updated_at)`.
`INSERT ... ON CONFLICT DO UPDATE WHERE excluded.updated_at > sync_rows.updated_at` for LWW upserts.

## MCP Server

McpSession Durable Object inside wimg-sync. Loads libwimg-compact.wasm,
pulls data from SyncRoom DO, decrypts, serves 17 MCP tools (8 read + 9 write).

Claude.ai connector: `URL: https://wimg-sync.mili-my.name/mcp`, `Auth: Bearer <sync-key>`
