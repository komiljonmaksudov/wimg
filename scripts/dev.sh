#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Local sync server (wimg-sync-zig) on :8787 with its own dev database.
echo "Starting wimg local dev..."
echo "  Sync API: http://localhost:8787 (native Zig server)"
echo ""

cd "$ROOT/wimg-sync-zig"
zig build
PORT=8787 WIMG_SYNC_DB="$ROOT/wimg-sync-zig/dev.db" exec ./zig-out/bin/wimg-sync
