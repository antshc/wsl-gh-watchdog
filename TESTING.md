# Testing

## Probe Smoke Test

Verifies that the probe Docker image is correctly built, runs as root,
mounts the host GitHub CLI config read-only, and successfully executes `gh issue view`.

### Prerequisites

- Docker installed and running
- GitHub CLI authenticated on the host (`~/.config/gh` contains valid credentials)
- Access to the target repository (`antshc/brain`) from the host gh session

### Steps

1. **Build the probe image:**

   ```bash
   docker build -t antshc/watchdog-gh:latest .
   ```

2. **Verify the image runs as root:**

   ```bash
   docker run --rm antshc/watchdog-gh:latest 'id'
   ```

   Expected output contains `uid=0(root)`.

3. **Run the probe with a real `gh issue view` call:**

   ```bash
   docker run --rm \
     -v ~/.config/gh:/root/.config/gh:ro \
     -e HOME=/root \
     antshc/watchdog-gh:latest \
     'timeout 20 gh issue view 1 --repo antshc/brain >/dev/null'
   ```

   Expected: exit code `0` and no error output.

4. **Confirm exit code:**

   ```bash
   echo "Exit code: $?"
   ```

   Expected output: `Exit code: 0`

### Pass Criteria

- Step 2 output shows `uid=0(root)` — container runs as root.
- Step 3 exits with code `0` — probe successfully authenticated and retrieved the issue.
- No `gh: command not found` or authentication errors.

---

## Watchdog Logic Test

Verifies that the watchdog script correctly counts consecutive probe failures,
triggers a Docker restart after hitting `FAIL_LIMIT`, resets the counter, and
logs both failures and restarts to `LOG_FILE`. No real Docker or service commands
are needed — both are replaced with stubs.

### Prerequisites

- Bash available
- `docker-github-watchdog.sh` present in the repository root

### Steps

1. **Create an always-fail probe stub:**

   ```bash
   STUB_DIR=$(mktemp -d)
   cat > "$STUB_DIR/fake-docker" << 'EOF'
   #!/usr/bin/env bash
   exit 1
   EOF
   chmod +x "$STUB_DIR/fake-docker"
   ```

2. **Create a service stub that records calls:**

   ```bash
   cat > "$STUB_DIR/fake-service" << 'EOF'
   #!/usr/bin/env bash
   echo "fake-service called: $*" >> "$STUB_DIR/service-calls.log"
   EOF
   chmod +x "$STUB_DIR/fake-service"
   ```

   > Note: replace `$STUB_DIR` with the actual path printed in step 1.

3. **Run the watchdog with stubs (terminates automatically after restart + next cycle timeout):**

   ```bash
   LOG=$(mktemp)
   DOCKER_CMD="$STUB_DIR/fake-docker" \
   SERVICE_CMD="$STUB_DIR/fake-service" \
   LOG_FILE="$LOG" \
   FAIL_LIMIT=2 \
   SLEEP_SECONDS=0 \
   timeout 5 bash docker-github-watchdog.sh || true
   ```

   The `timeout 5` kills the infinite loop after enough cycles have run.

4. **Verify the log contains two failure entries and one restart entry:**

   ```bash
   grep -c 'probe failed' "$LOG"
   grep -c 'restarting Docker' "$LOG"
   ```

   Expected: `grep -c 'probe failed'` prints `2` (or more); `grep -c 'restarting Docker'` prints `1` (or more).

5. **Verify the service stub was called:**

   ```bash
   cat "$STUB_DIR/service-calls.log"
   ```

   Expected output contains `fake-service called: docker restart`.

### Pass Criteria

- Log file contains at least 2 `probe failed` lines before the first restart.
- Log file contains at least 1 `restarting Docker` line.
- `$STUB_DIR/service-calls.log` exists and contains `docker restart`.

---

## Install

Copy the script and service files into place, then enable the service:

```bash
sudo cp docker-github-watchdog.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/docker-github-watchdog.sh
sudo cp docker-github-watchdog.service /etc/systemd/system/
sudo cp logrotate.d/docker-github-watchdog /etc/logrotate.d/
sudo systemctl daemon-reload
sudo systemctl enable docker-github-watchdog
sudo systemctl start docker-github-watchdog
```

To override any default parameter without editing the unit file:

```bash
sudo systemctl edit docker-github-watchdog
```

Add an `[Service]` block with the desired `Environment=KEY=value` overrides, then
`sudo systemctl daemon-reload && sudo systemctl restart docker-github-watchdog`.

---

## Service Lifecycle Test

Verifies that the systemd service starts, runs probes, writes to the log file,
and responds correctly to `systemctl stop` and `systemctl restart`.

### Prerequisites

- systemd available (native Linux or WSL2 with systemd enabled)
- Docker installed and running
- GitHub CLI authenticated on the host (`~/.config/gh` contains valid credentials)
- Probe image built: `docker build -t antshc/watchdog-gh:latest .`
- Script and service installed (see [Install](#install) above)

### Steps

1. **Confirm the service is enabled and start it:**

   ```bash
   sudo systemctl enable docker-github-watchdog
   sudo systemctl start docker-github-watchdog
   ```

2. **Check the service status:**

   ```bash
   systemctl status docker-github-watchdog
   ```

   Expected: `Active: active (running)` and the main PID is shown.

3. **Verify the watchdog is writing to the log file:**

   ```bash
   sleep 10
   tail -20 /var/log/docker-github-watchdog.log
   ```

   Expected: log entries appear showing probe results (success or failure lines).

4. **Stop the service:**

   ```bash
   sudo systemctl stop docker-github-watchdog
   ```

5. **Confirm the service has stopped:**

   ```bash
   systemctl status docker-github-watchdog
   ```

   Expected: `Active: inactive (dead)`.

6. **Restart the service and confirm it recovers:**

   ```bash
   sudo systemctl restart docker-github-watchdog
   systemctl status docker-github-watchdog
   ```

   Expected: `Active: active (running)` again with a new PID.

7. **Disable the service:**

   ```bash
   sudo systemctl disable docker-github-watchdog
   ```

   Expected: symlink removed from the wants directory; service will not start on
   next boot.

### Pass Criteria

- Step 2 shows `active (running)` — service started successfully.
- Step 3 shows log entries — watchdog is executing probes and writing output.
- Step 5 shows `inactive (dead)` — service stopped cleanly.
- Step 6 shows `active (running)` with a new PID — service restarted correctly.
- Step 7 completes without error — service disabled from auto-start.
