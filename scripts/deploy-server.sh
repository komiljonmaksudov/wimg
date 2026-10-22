#!/bin/bash
# Build and ship everything the Hetzner VPS serves, straight from this Mac.
# No GitHub CI involved — CI only builds iOS/Android and the GitHub Release.
#
# Usage:
#   ./scripts/deploy-server.sh          # web app + sync server
#   ./scripts/deploy-server.sh web      # web app only  (wimg.mili-my.name)
#   ./scripts/deploy-server.sh sync     # sync server only (wimg-sync.mili-my.name)
#
# VPS defaults to the `hetzner` alias in ~/.ssh/config; override with VPS=root@<ip>.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export VPS="${VPS:-hetzner}"
WHAT="${1:-all}"
# The VPS runs Ubuntu 24.04 on x86_64 (glibc 2.39). Cross-compiling from macOS
# needs the target spelled out, or zig builds a Mac binary.
SYNC_TARGET="x86_64-linux-gnu.2.39"

die() { echo "error: $1" >&2; exit 1; }

case "$WHAT" in
  all|web|sync) ;;
  *) die "unknown target '$WHAT' (use: all, web, sync)" ;;
esac

ssh -o ConnectTimeout=10 "$VPS" true || die "can't reach $VPS over SSH"

# Same amalgamation CI downloads; gitignored, so fetch once.
if [[ ! -f libwimg/vendor/sqlite3.c ]]; then
  echo "==> Fetching SQLite amalgamation"
  tmp="$(mktemp -d)"
  curl -fsSL https://www.sqlite.org/2026/sqlite-amalgamation-3520000.zip -o "$tmp/sqlite.zip"
  unzip -q -o "$tmp/sqlite.zip" -d "$tmp"
  cp "$tmp"/sqlite-amalgamation-3520000/sqlite3.{c,h} libwimg/vendor/
  rm -rf "$tmp"
fi

if [[ "$WHAT" == all || "$WHAT" == web ]]; then
  echo "==> Building web app"
  ./scripts/build-wasm.sh
  (cd wimg-web && bun install --frozen-lockfile && bun run build)
  ./infra/scripts/deploy-web.sh --no-build
fi

if [[ "$WHAT" == all || "$WHAT" == sync ]]; then
  echo "==> Building sync server for $SYNC_TARGET"
  (cd wimg-sync-zig && zig build --release=safe -Dtarget="$SYNC_TARGET")
  file wimg-sync-zig/zig-out/bin/wimg-sync | grep -q 'ELF 64-bit.*x86-64' ||
    die "wimg-sync is not a Linux x86_64 binary — refusing to ship it"
  ./infra/scripts/deploy.sh
fi

echo "==> Deployed ($WHAT) to $VPS"
