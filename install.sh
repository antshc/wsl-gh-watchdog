#!/usr/bin/env bash
set -euo pipefail

# ─── Detect real invoking user ────────────────────────────────────────────────
# Works correctly when run directly, via sudo, or piped from curl | bash
REAL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
GH_CONFIG="$REAL_HOME/.config/gh"

# ─── Prerequisite checks ──────────────────────────────────────────────────────
if [[ "$(cat /proc/1/comm 2>/dev/null)" != "systemd" ]]; then
    echo "ERROR: systemd is not PID 1." >&2
    echo "       Enable systemd in WSL by adding to /etc/wsl.conf:" >&2
    echo "         [boot]" >&2
    echo "         systemd=true" >&2
    echo "       Then restart WSL: wsl.exe --shutdown" >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found in PATH. Install Docker first." >&2
    exit 1
fi

echo "Detected GH_CONFIG: $GH_CONFIG"
echo ""

# ─── Pull probe image ─────────────────────────────────────────────────────────
echo "==> Pulling probe image ..."
docker pull antshc/watchdog-gh:latest

# ─── Download and extract runtime artifacts ───────────────────────────────────
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "==> Downloading runtime artifacts ..."
curl -fsSL https://github.com/antshc/wsl-gh-watchdog/releases/latest/download/runtime.tar.gz \
    | tar -xz -C "$TMPDIR"

# ─── Install watchdog script ──────────────────────────────────────────────────
echo "==> Installing watchdog script ..."
sudo install -m 0755 "$TMPDIR/runtime/docker-github-watchdog.sh" /usr/local/bin/docker-github-watchdog.sh

# ─── Install systemd unit (GH_CONFIG substituted at install time) ─────────────
echo "==> Installing systemd unit ..."
sed "s|Environment=GH_CONFIG=.*|Environment=GH_CONFIG=${GH_CONFIG}|" \
    "$TMPDIR/runtime/docker-github-watchdog.service" \
    | sudo tee /etc/systemd/system/docker-github-watchdog.service > /dev/null

# ─── Install logrotate config ─────────────────────────────────────────────────
echo "==> Installing logrotate config ..."
sudo install -m 0644 "$TMPDIR/runtime/logrotate.d/docker-github-watchdog" /etc/logrotate.d/docker-github-watchdog

# ─── Enable and start service ─────────────────────────────────────────────────
echo "==> Enabling service ..."
sudo systemctl daemon-reload
sudo systemctl enable docker-github-watchdog

if sudo systemctl is-active --quiet docker-github-watchdog; then
    echo "==> Service is running — restarting to apply changes ..."
    sudo systemctl restart docker-github-watchdog
else
    echo "==> Starting service ..."
    sudo systemctl start docker-github-watchdog
fi

# ─── Success summary ──────────────────────────────────────────────────────────
echo ""
echo "=== Install complete ==="
echo ""
sudo systemctl status docker-github-watchdog --no-pager || true
echo ""
echo "Tail logs with:"
echo "  tail -f /var/log/docker-github-watchdog.log"
