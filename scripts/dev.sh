#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Sync backend: the Cloudflare Worker by default, or the native Zig server
# (wimg-sync-zig) with WIMG_NATIVE_SYNC=1. Either way it listens on :8787 so the
# web client's dev URL (config.ts → http://<host>:8787) works unchanged.
NATIVE="${WIMG_NATIVE_SYNC:-0}"

echo "Starting wimg local dev..."
echo "  Sync API: http://localhost:8787 ($([ "$NATIVE" = "1" ] && echo "native Zig server" || echo "Cloudflare Worker"))"
echo "  Web app:  http://localhost:5173"
echo ""

if [ "$NATIVE" = "1" ]; then
  # Build once, then run on :8787 with a local dev DB.
  (cd "$ROOT/wimg-sync-zig" && zig build && PORT=8787 WIMG_SYNC_DB="$ROOT/wimg-sync-zig/dev.db" ./zig-out/bin/wimg-sync) &
  SYNC_PID=$!
else
  # Cloudflare Worker (--ip 0.0.0.0 for LAN access from a phone).
  (cd "$ROOT/wimg-sync" && bunx wrangler dev --ip 0.0.0.0 --port 8787) &
  SYNC_PID=$!
fi

# Start web dev server in background
(cd "$ROOT/wimg-web" && bun run dev --host) &
WEB_PID=$!

# Cleanup both on exit
trap "kill $SYNC_PID $WEB_PID 2>/dev/null" EXIT

wait
