# Testing

## Probe Smoke Test

Verifies that the probe Docker image is correctly built, runs as a non-root user,
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

2. **Verify the image runs as uid 1000:**

   ```bash
   docker run --rm antshc/watchdog-gh:latest 'id'
   ```

   Expected output contains `uid=1000(dev)`.

3. **Run the probe with a real `gh issue view` call:**

   ```bash
   docker run --rm \
     -v /home/dev/.config/gh:/home/dev/.config/gh:ro \
     -e HOME=/home/dev \
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

- Step 2 output shows `uid=1000(dev)` — container runs as non-root.
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
