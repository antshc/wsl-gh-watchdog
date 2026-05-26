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
