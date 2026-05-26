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
