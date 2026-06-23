#!/bin/bash
# wimg-sync deploy — push config + binary to the VPS.
#
# Usage:
#   VPS=root@<vps-ip> ./infra/scripts/deploy.sh [--config-only]
#
# --config-only skips binary upload (use when only Caddyfile or systemd units changed).

set -euo pipefail

VPS="${VPS:-}"
if [[ -z "$VPS" ]]; then
	echo "Set VPS=root@<ip> first." >&2
	exit 1
fi

CONFIG_ONLY=0
if [[ "${1:-}" == "--config-only" ]]; then
	CONFIG_ONLY=1
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

echo "==> Uploading Caddyfile"
scp infra/Caddyfile "$VPS:/etc/caddy/Caddyfile"

echo "==> Uploading systemd units"
scp infra/systemd/wimg-sync.service "$VPS:/etc/systemd/system/wimg-sync.service"
scp infra/systemd/wimg-restic.service "$VPS:/etc/systemd/system/wimg-restic.service"
scp infra/systemd/wimg-restic.timer "$VPS:/etc/systemd/system/wimg-restic.timer"

if [[ $CONFIG_ONLY -eq 0 ]]; then
	BIN="wimg-sync-zig/zig-out/bin/wimg-sync"
	if [[ ! -f "$BIN" ]]; then
		echo "Binary not found at $BIN — build it first (Phase 1 not done yet?)." >&2
		exit 1
	fi
	echo "==> Uploading wimg-sync binary"
	scp "$BIN" "$VPS:/usr/local/bin/wimg-sync.new"
	# Atomic swap — never leaves the binary in a half-written state
	ssh "$VPS" 'mv /usr/local/bin/wimg-sync.new /usr/local/bin/wimg-sync && chmod 0755 /usr/local/bin/wimg-sync'
fi

echo "==> Reloading services"
ssh "$VPS" 'systemctl daemon-reload && systemctl reload caddy'
if [[ $CONFIG_ONLY -eq 0 ]]; then
	ssh "$VPS" 'systemctl restart wimg-sync'
fi

echo "==> Done."
ssh "$VPS" 'systemctl --no-pager --lines=0 status wimg-sync caddy || true'
