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

# ─── Install watchdog script ──────────────────────────────────────────────────
echo "==> Installing watchdog script ..."
sudo tee /usr/local/bin/docker-github-watchdog.sh > /dev/null <<'WATCHDOG_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-antshc/watchdog-gh:latest}"
GH_CONFIG="${GH_CONFIG:-/home/dev/.config/gh}"
REPO="${REPO:-antshc/brain}"
ISSUE="${ISSUE:-1}"
LOG_FILE="${LOG_FILE:-/var/log/docker-github-watchdog.log}"
FAIL_LIMIT="${FAIL_LIMIT:-3}"
SLEEP_SECONDS="${SLEEP_SECONDS:-60}"
DOCKER_CMD="${DOCKER_CMD:-docker}"
SERVICE_CMD="${SERVICE_CMD:-service}"

FAIL_COUNT=0

while true; do
    if "$DOCKER_CMD" run --rm \
        -v "$GH_CONFIG:/home/dev/.config/gh:ro" \
        -e HOME=/home/dev \
        "$IMAGE" \
        "timeout 20 gh issue view $ISSUE --repo $REPO >/dev/null 2>&1"; then
        FAIL_COUNT=0
    else
        FAIL_COUNT=$(( FAIL_COUNT + 1 ))
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] probe failed (failure $FAIL_COUNT of $FAIL_LIMIT)" >> "$LOG_FILE"

        if (( FAIL_COUNT >= FAIL_LIMIT )); then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] failure limit reached, restarting Docker" >> "$LOG_FILE"
            "$SERVICE_CMD" docker restart
            FAIL_COUNT=0
            sleep 10
        fi
    fi

    sleep "$SLEEP_SECONDS"
done
WATCHDOG_SCRIPT
sudo chmod +x /usr/local/bin/docker-github-watchdog.sh

# ─── Install systemd unit (GH_CONFIG substituted at install time) ─────────────
echo "==> Installing systemd unit ..."
sudo tee /etc/systemd/system/docker-github-watchdog.service > /dev/null <<SERVICE_UNIT
[Unit]
Description=Docker GitHub Connectivity Watchdog
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/docker-github-watchdog.sh
Restart=always
RestartSec=10
Environment=IMAGE=antshc/watchdog-gh:latest
Environment=GH_CONFIG=${GH_CONFIG}
Environment=REPO=antshc/brain
Environment=ISSUE=1
Environment=LOG_FILE=/var/log/docker-github-watchdog.log
Environment=FAIL_LIMIT=3
Environment=SLEEP_SECONDS=60

[Install]
WantedBy=multi-user.target
SERVICE_UNIT

# ─── Install logrotate config ─────────────────────────────────────────────────
echo "==> Installing logrotate config ..."
sudo tee /etc/logrotate.d/docker-github-watchdog > /dev/null <<'LOGROTATE_CONF'
/var/log/docker-github-watchdog.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    copytruncate
}
LOGROTATE_CONF

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
