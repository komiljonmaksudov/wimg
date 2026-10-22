# wimg Architecture

## Overview

```
libwimg (Zig)
├── sqlite3.c (amalgamation, compiled in — no external dep)
├── src/
│   ├── root.zig        C ABI exports — the public API
│   ├── db.zig          SQLite wrapper + schema + migrations
│   ├── parser.zig      CSV parsing (Comdirect, Trade Republic, Scalable)
│   ├── categories.zig  Categorization (keyword rules)
│   ├── summary.zig     Monthly summaries, debt tracking, goals
│   ├── types.zig       Transaction, Category, Summary structs
│   ├── gguf.zig        GGUF v3 file parser
│   ├── quants.zig      Dequantization (Q4_K, Q6_K, Q8_0, F16) + vector math
│   ├── tokenizer.zig   SentencePiece Unigram tokenizer (Viterbi, vocab/scores from GGUF)
│   └── embed.zig       BERT transformer forward pass (12 layers, e5-small)
│
├── → libwimg.wasm      (wasm32-freestanding) ← web
└── → libwimg.a         (aarch64-apple-ios)   ← iOS / macOS

wimg-web  (Svelte 5 + TailwindCSS + LayerChart)
├── loads libwimg.wasm
├── OPFS for SQLite persistence (offline, no server)
├── PWA — installable, works fully offline
└── thin shell: UI only, zero business logic

wimg-ios  (SwiftUI)
├── links libwimg.a
├── SQLite file at ~/Documents/wimg.db
└── thin shell: UI only, zero business logic
```

### Data flow

```
User drops CSV
  → wimg-web passes bytes to libwimg.wasm
  → parser.zig parses Comdirect/TR/Scalable format
  → categories.zig assigns categories (keyword rules + smart categorize)
  → db.zig writes to SQLite (via OPFS on web, file on iOS)
  → root.zig returns JSON to Svelte
  → Svelte renders transaction list
```

### Sync (Phase 4)

Last-write-wins via `updated_at` timestamp on every row.
No CRDTs, no Automerge, no conflict resolution complexity.
One person, two devices — whoever saved last is right.

Sync via Cloudflare Durable Objects + WebSocket Hibernation API.
Real-time: change on one device → appears on others within 1-2 seconds.

### Offline

Web: OPFS (Origin Private File System) — SQLite writes directly to a local
browser file. Works offline. Persists across sessions. No server needed.

Requires these headers (Vite dev + production host):

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

iOS: regular file on disk. Always offline-first by nature.

### Pure Zig Inference Engine

Local embedding model runs entirely in Zig — no ggml, no llama.cpp, no C++ deps.
~500 lines of Zig for a complete BERT forward pass on wasm32-freestanding.

**Model:** multilingual-e5-small (118M params, 12 layers, 384-dim, Q8_0 GGUF, ~125MB)

```
GGUF file (from HuggingFace)
  → gguf.zig parses header, KV metadata, tensor directory
  → tokenizer.zig loads vocab + scores from GGUF metadata
  → embed.zig loads tensor weights (Q8_0 quantized)

Input text ("REWE MARKT BERLIN")
  → tokenizer.zig: SentencePiece Unigram (Viterbi) → token IDs [▁RE, WE, ▁MAR, KT, ...]
  → embed.zig: 12-layer BERT forward pass
     1. Token embeddings + position embeddings (lookup)
     2. Per layer: self-attention (Q/K/V) → FFN (up → GELU → down)
     3. RMSNorm after each sublayer
     4. Mean pooling over sequence → L2 normalize
  → 384-dim float32 vector output
  → Stored in embeddings table (1536 bytes per transaction)

Smart categorize:
  → Cosine similarity between uncategorized tx and categorized tx embeddings
  → Sign-aware: only matches income↔income, expense↔expense
  → Threshold > 0.7 → assign same category

Search (Phase 5.7 — planned):
  → FTS5 full-text search (primary) for 5K-10K+ transactions
  → Fuzzy substring via LIKE as fallback
  → Embeddings as optional secondary re-ranking signal
```

**Key implementation details:**

- Q8_0 dequantization: 32 int8 values + f16 scale per block → f32
- All computation in f32 (no SIMD, single-threaded — fast enough for WASM)
- Model loaded via `@wasmMemoryGrow` (too large for 64MB FBA)
- Tokenizer vocab/scores in file-level statics (too large for 1MB stack)
- SentencePiece Unigram tokenizer with Viterbi DP (not BPE — model type is Unigram)
- GGUF patched with `tokenizer.ggml.scores` (original converter omitted them)
- Model stored in OPFS (persistent, not affected by SW cache cleanup)

---

## Tech Stack

| Layer           | Choice                                    | Why                                                   |
| --------------- | ----------------------------------------- | ----------------------------------------------------- |
| Shared core     | Zig 0.17.0                                | Single source of truth for all logic                  |
| Storage         | SQLite 3.52.0 (amalgamation, compiled in) | Local, queryable, no deps                             |
| Web UI          | Svelte 5 + TailwindCSS + LayerChart       | Reactive, lightweight, Svelte-native charts           |
| Web persistence | OPFS                                      | SQLite-on-browser, offline, no server                 |
| iOS UI          | SwiftUI                                   | Native, links libwimg.a via C ABI                     |
| Sync            | CF Durable Objects + WebSocket + LWW      | Real-time, hibernation = cost-efficient               |
| AI              | Local embeddings (Zig)                    | Pure Zig inference for smart categorization            |
| Embeddings      | multilingual-e5-small (Q8_0 GGUF, ~125MB) | 384-dim vectors, smart categorization (tx↔tx cosine)  |
| Search          | SQLite FTS5 (planned)                     | Full-text search for 5K-10K+ transactions              |
| FinTS           | Pure Zig (fints.zig + mt940.zig)          | No external deps, native-only, direct bank connection |
| MCP server      | CF Worker DO + libwimg.wasm + Zod         | Remote MCP via POST /mcp, Bearer auth = sync key      |
