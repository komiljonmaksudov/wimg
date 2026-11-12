#!/bin/bash
# wimg landing page deploy — build the static site and sync it to the VPS.
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
	echo "==> Building wimg-site"
	python3 wimg-site/build.py
fi

if [[ ! -f wimg-site/public/index.html || ! -f wimg-site/public/app.js ]]; then
	echo "wimg-site/public is incomplete — did the build run?" >&2
	exit 1
fi

echo "==> Syncing to $VPS:/var/www/wimg"
ssh "$VPS" 'mkdir -p /var/www/wimg'
# --delete so the old SvelteKit build and removed assets don't linger.
rsync -az --delete wimg-site/public/ "$VPS:/var/www/wimg/"
ssh "$VPS" 'chown -R caddy:caddy /var/www/wimg 2>/dev/null || chown -R www-data:www-data /var/www/wimg 2>/dev/null || true'

# Check by hitting the box's public IP with the right SNI/Host, bypassing DNS.
# Not 127.0.0.1: the main Caddyfile sets `default_bind` to the public addresses
# only (tailscaled owns :443 on the Tailscale IPs), so loopback never answers.
echo "==> Done. Serving check (bypasses DNS):"
IP="$(ssh -G "$VPS" | awk '/^hostname /{print $2}')"  # works for aliases and user@ip
curl -sS -o /dev/null -m10 -w "index.html -> HTTP %{http_code}\n" \
	--resolve "wimg.komiljonmaksudov.com:443:$IP" https://wimg.komiljonmaksudov.com/ || true
