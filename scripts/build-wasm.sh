#!/bin/bash
set -euo pipefail

# Build libwimg for WASM: the compact variant (16MB FBA + 8MB VFS + 8MB heap)
# used by the wimg-sync Cloudflare Worker, kept as a rollback for the native
# Zig sync server. The web app is gone, so there is no other WASM build.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/libwimg"

echo "=== Building libwimg.wasm (compact) ==="
zig build --release=small
cp zig-out/bin/libwimg.wasm "$ROOT/wimg-sync/libwimg-compact.wasm"
echo "=== Copied to wimg-sync/libwimg-compact.wasm ==="
ls -lh "$ROOT/wimg-sync/libwimg-compact.wasm"
