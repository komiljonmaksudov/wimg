#!/bin/bash
# wimg web app deploy — build the static SPA and sync it to the VPS.
#
# Usage:
#   VPS=root@<vps-ip> ./infra/scripts/deploy-web.sh [--no-build]
#
# Serves from /var/www/wimg, matching the existing /var/www/{eigenheim,packsil}
# layout. The Caddy site block lives in infra/wimg-web.caddy and is installed by
# deploy.sh — run that at least once before this.

set -euo pipefail

VPS="${VPS:-}"
if [[ -z "$VPS" ]]; then
	echo "Set VPS=root@<ip> first." >&2
	exit 1
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ "${1:-}" != "--no-build" ]]; then
	echo "==> Building wimg-web"
	(cd wimg-web && bun run build)
fi

if [[ ! -f wimg-web/build/index.html ]]; then
	echo "wimg-web/build/index.html missing — did the build run?" >&2
	exit 1
fi

# The WASM binary is gitignored and produced by scripts/build-wasm.sh into
# wimg-web/static/. Without it the app loads and then dies on init, so fail
# loudly here rather than shipping a broken site.
if ! ls wimg-web/build/*.wasm >/dev/null 2>&1; then
	echo "No .wasm in wimg-web/build — run ./scripts/build-wasm.sh first." >&2
	exit 1
fi

echo "==> Syncing to $VPS:/var/www/wimg"
ssh "$VPS" 'mkdir -p /var/www/wimg'
# --delete so removed assets don't linger; the dir holds nothing but build output.
rsync -az --delete wimg-web/build/ "$VPS:/var/www/wimg/"
ssh "$VPS" 'chown -R caddy:caddy /var/www/wimg 2>/dev/null || chown -R www-data:www-data /var/www/wimg 2>/dev/null || true'

# Check by hitting the box's public IP with the right SNI/Host, bypassing DNS.
# Not 127.0.0.1: the main Caddyfile sets `default_bind` to the public addresses
# only (tailscaled owns :443 on the Tailscale IPs), so loopback never answers.
# -k because until DNS points here, Caddy has no valid cert for the name yet.
echo "==> Done. Serving check (bypasses DNS):"
IP="${VPS##*@}"
curl -sSk -o /dev/null -m10 -w "index.html -> HTTP %{http_code}\n" \
	--resolve "wimg.mili-my.name:443:$IP" https://wimg.mili-my.name/ || true
