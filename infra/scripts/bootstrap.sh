#!/bin/bash
# wimg-sync VPS bootstrap — one command to take a fresh Hetzner box to "ready for Phase 1".
#
# Prerequisites:
#   1. infra/restic.env exists locally (copy from restic.env.example, fill in R2 creds)
#   2. SSH key auth works: `ssh root@<vps>` succeeds without password
#   3. Hetzner CX11 running Ubuntu 24.04
#
# Usage:
#   ./infra/scripts/bootstrap.sh root@<vps-ip>
#
# What this does end-to-end:
#   1. Ships setup-vps.sh + config files up via tar+ssh (one round trip)
#   2. Runs setup-vps.sh on the VPS (installs caddy, restic, hardens, etc.)
#   3. Drops Caddyfile + systemd units in place
#   4. Drops restic.env into /etc/wimg/ with strict perms
#   5. Initializes the restic repo on R2 (idempotent)
#   6. Enables wimg-restic.timer (the sync service is enabled but stays inactive
#      until Phase 1 lands the binary — that's fine)
#   7. Reloads caddy
#   8. Shows status

set -euo pipefail

VPS="${1:-}"
if [[ -z "$VPS" ]]; then
	echo "Usage: $0 root@<vps-ip>" >&2
	exit 1
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ ! -f infra/restic.env ]]; then
	echo "infra/restic.env not found. Copy from restic.env.example and fill in R2 creds first." >&2
	exit 1
fi

# Sanity-check the env file has real values, not the placeholders
if grep -qE '<R2_ACCOUNT_ID>|<r2-access-key|<r2-secret|<long-random' infra/restic.env; then
	echo "infra/restic.env still contains placeholder values. Edit it first." >&2
	exit 1
fi

echo "==> Uploading provisioning bundle to $VPS"
# One tar stream over ssh — faster than multiple scp calls, atomic-ish
tar czf - \
	infra/scripts/setup-vps.sh \
	infra/Caddyfile \
	infra/systemd/wimg-sync.service \
	infra/systemd/wimg-restic.service \
	infra/systemd/wimg-restic.timer \
	infra/restic.env \
	| ssh "$VPS" 'mkdir -p /root/wimg-bootstrap && tar xzf - -C /root/wimg-bootstrap'

echo "==> Running setup-vps.sh"
ssh "$VPS" 'bash /root/wimg-bootstrap/infra/scripts/setup-vps.sh'

echo "==> Installing config files"
ssh "$VPS" bash <<'REMOTE'
set -euo pipefail
cd /root/wimg-bootstrap

# Caddy config
install -o root -g root -m 0644 infra/Caddyfile /etc/caddy/Caddyfile

# systemd units
install -o root -g root -m 0644 infra/systemd/wimg-sync.service    /etc/systemd/system/wimg-sync.service
install -o root -g root -m 0644 infra/systemd/wimg-restic.service  /etc/systemd/system/wimg-restic.service
install -o root -g root -m 0644 infra/systemd/wimg-restic.timer    /etc/systemd/system/wimg-restic.timer

# restic env (mode 0640, root:wimg — the wimg user reads it via EnvironmentFile)
install -o root -g wimg -m 0640 infra/restic.env /etc/wimg/restic.env

systemctl daemon-reload
systemctl reload caddy
REMOTE

echo "==> Initializing restic R2 repo (idempotent)"
# `restic init` errors if the repo already exists — swallow that one specific error.
ssh "$VPS" '
	set -e
	export $(grep -v "^#" /etc/wimg/restic.env | xargs)
	if sudo -u wimg --preserve-env restic snapshots >/dev/null 2>&1; then
		echo "Repo already initialized — skipping."
	else
		sudo -u wimg --preserve-env restic init
	fi
'

echo "==> Enabling timer + sync service (sync stays inactive until Phase 1 binary lands)"
ssh "$VPS" '
	systemctl enable wimg-restic.timer
	systemctl start wimg-restic.timer
	systemctl enable wimg-sync.service   # enabled but inactive — will start when binary arrives
'

echo "==> Cleaning up bootstrap files on VPS"
ssh "$VPS" 'rm -rf /root/wimg-bootstrap'

echo ""
echo "==> Status"
ssh "$VPS" 'systemctl list-timers wimg-restic --no-pager; echo; systemctl --no-pager status caddy --lines=0'

echo ""
echo "==> Done. Phase 0 complete on $VPS."
echo ""
echo "Next:"
echo "  - Add a staging DNS record (e.g. hetzner.wimg-sync.mili-my.name -> $VPS IP)"
echo "    so Caddy can fetch a TLS cert before the production cutover."
echo "  - Phase 1: build the Zig sync server, then run:"
echo "      VPS=$VPS ./infra/scripts/deploy.sh"
