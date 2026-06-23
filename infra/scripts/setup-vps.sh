#!/bin/bash
# wimg-sync VPS provisioning — idempotent first-boot setup.
#
# Run on a fresh Hetzner CX11 Ubuntu 24.04 box as root:
#   curl -fsSL <raw-url-to-this-file> | bash
# or scp it up and run locally:
#   scp setup-vps.sh root@<vps-ip>:/root/
#   ssh root@<vps-ip> bash /root/setup-vps.sh
#
# What this does:
#   1. Hardens SSH (key-only auth, no root password login)
#   2. Configures the firewall (allow 22 + 443 only)
#   3. Creates the `wimg` system user
#   4. Creates /var/lib/wimg and /etc/wimg directories
#   5. Installs Caddy (reverse proxy + auto-TLS)
#   6. Installs restic (backup tool)
#   7. Disables core dumps (would contain in-memory sync keys)
#   8. Sets timezone to Europe/Berlin so restic cron runs at local 03:00
#
# What you still do manually after this runs:
#   - Drop the wimg-sync binary at /usr/local/bin/wimg-sync (Phase 1)
#   - Drop the Caddyfile at /etc/caddy/Caddyfile and `systemctl reload caddy`
#   - Drop the systemd unit files and `systemctl enable --now wimg-sync wimg-restic.timer`
#   - Fill in /etc/wimg/restic.env from restic.env.example
#   - Initialize the restic repo: `sudo -u wimg restic init` (one-time)
#   - Point DNS A record for wimg-sync.mili-my.name at this VPS

set -euo pipefail

# Refuse to run if we're not root — most steps need root, and the user/file
# ownership shifts get confusing otherwise.
if [[ $EUID -ne 0 ]]; then
	echo "Run as root (or via sudo)." >&2
	exit 1
fi

echo "==> Updating apt cache"
apt-get update -qq
apt-get upgrade -y -qq

echo "==> Installing base packages"
apt-get install -y -qq \
	ufw \
	curl \
	ca-certificates \
	gnupg \
	debian-keyring \
	debian-archive-keyring \
	apt-transport-https \
	cryptsetup \
	sqlite3 \
	restic

echo "==> Creating wimg user (if not exists)"
if ! id wimg &>/dev/null; then
	useradd --system --shell /usr/sbin/nologin --home /var/lib/wimg --create-home wimg
fi

echo "==> Creating directories"
install -d -o wimg -g wimg -m 0750 /var/lib/wimg
install -d -o wimg -g wimg -m 0750 /var/cache/restic
install -d -o root -g wimg -m 0750 /etc/wimg

echo "==> Installing Caddy (apt repo + package)"
if ! command -v caddy &>/dev/null; then
	curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
		| gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
	curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
		> /etc/apt/sources.list.d/caddy-stable.list
	apt-get update -qq
	apt-get install -y -qq caddy
fi

echo "==> Disabling core dumps (kernel + systemd + limits.conf)"
# limits.conf — applies to all users at next login
if ! grep -q '^\* hard core 0$' /etc/security/limits.conf; then
	echo '* hard core 0' >>/etc/security/limits.conf
	echo '* soft core 0' >>/etc/security/limits.conf
fi
# sysctl — kernel-level disable
cat >/etc/sysctl.d/50-no-core.conf <<'EOF'
kernel.core_pattern=|/bin/false
fs.suid_dumpable=0
EOF
sysctl -p /etc/sysctl.d/50-no-core.conf >/dev/null

echo "==> Configuring SSH (key-only, no root password)"
# Backup once; only touch if we haven't already
if [[ ! -f /etc/ssh/sshd_config.bak ]]; then
	cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
fi
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
systemctl reload ssh || systemctl reload sshd

echo "==> Configuring ufw firewall (22 + 443)"
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow 22/tcp comment 'SSH' >/dev/null
ufw allow 443/tcp comment 'HTTPS (Caddy)' >/dev/null
ufw --force enable >/dev/null

echo "==> Setting timezone to Europe/Berlin"
timedatectl set-timezone Europe/Berlin

echo "==> Done."
echo ""
echo "Next steps (manual):"
echo "  1. scp infra/Caddyfile root@<vps>:/etc/caddy/Caddyfile && systemctl reload caddy"
echo "  2. scp infra/systemd/wimg-*.{service,timer} root@<vps>:/etc/systemd/system/"
echo "     systemctl daemon-reload"
echo "  3. cp infra/restic.env.example /etc/wimg/restic.env  # then fill in R2 creds"
echo "     chmod 600 /etc/wimg/restic.env && chown root:wimg /etc/wimg/restic.env"
echo "  4. sudo -u wimg /usr/local/bin/restic init  # one-time R2 repo init"
echo "  5. Drop the wimg-sync binary at /usr/local/bin/wimg-sync (Phase 1)"
echo "     systemctl enable --now wimg-sync wimg-restic.timer"
echo "  6. Point wimg-sync.mili-my.name DNS A record at this VPS"
