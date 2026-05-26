# wsl-gh-watchdog

A systemd service for WSL 2 that silently monitors Docker's GitHub connectivity and restarts Docker when it loses it.

## Overview

Docker running inside WSL 2 can silently lose GitHub connectivity — `gh` commands hang or fail, but Docker itself appears healthy. This watchdog detects that condition and self-heals by restarting the Docker daemon.

It works by repeatedly running a lightweight probe container (`antshc/watchdog-gh:latest`) that calls `gh issue view` against a known GitHub repo. Consecutive failures increment a counter; once the counter reaches the configured limit, the watchdog restarts Docker and resets the counter.

```
probe container → success → reset counter → sleep
                → failure → increment counter
                          → counter >= FAIL_LIMIT → restart Docker → reset counter → sleep
```

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/antshc/wsl-gh-watchdog/main/install.sh | bash
```

The script checks prerequisites, pulls the probe image, installs all files, and starts the service in one step. Re-running it is safe — it is idempotent.

## Prerequisites

### WSL 2 with systemd enabled

Check `/etc/wsl.conf`:

```bash
cat /etc/wsl.conf
```

You need a `[boot]` section with `systemd=true`:

```ini
[boot]
systemd=true
```

If it is missing, add it and restart WSL:

```bash
echo -e '[boot]\nsystemd=true' | sudo tee -a /etc/wsl.conf
wsl.exe --shutdown   # run from Windows, then reopen WSL
```

### Docker installed and running

```bash
docker info
```

### GitHub CLI authenticated on the host

The probe container mounts the host's `gh` config read-only. Ensure `gh` is authenticated:

```bash
ls ~/.config/gh/hosts.yml
```

If missing, run `gh auth login` on the host first.

## Installation

```bash
# Pull probe image
docker pull antshc/watchdog-gh:latest

# Install watchdog script
sudo cp docker-github-watchdog.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/docker-github-watchdog.sh

# Install service and logrotate config
sudo cp docker-github-watchdog.service /etc/systemd/system/
sudo cp logrotate.d/docker-github-watchdog /etc/logrotate.d/

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable docker-github-watchdog
sudo systemctl start docker-github-watchdog
```

## Configuration

All settings are controlled by environment variables. The defaults work out of the box if your `gh` config lives at `/home/dev/.config/gh`.

| Variable | Default | Description |
|---|---|---|
| `IMAGE` | `antshc/watchdog-gh:latest` | Probe container image |
| `GH_CONFIG` | `/home/dev/.config/gh` | Host path to `gh` config, mounted read-only into the probe container |
| `REPO` | `antshc/brain` | GitHub repo used for the connectivity probe |
| `ISSUE` | `1` | Issue number passed to `gh issue view` |
| `LOG_FILE` | `/var/log/docker-github-watchdog.log` | Path to the watchdog log file |
| `FAIL_LIMIT` | `3` | Consecutive probe failures before Docker is restarted |
| `SLEEP_SECONDS` | `60` | Seconds between probe cycles |

To override variables without editing the service file directly, use a drop-in override:

```bash
sudo systemctl edit docker-github-watchdog
```

Add overrides in the editor that opens:

```ini
[Service]
Environment=GH_CONFIG=/home/myuser/.config/gh
Environment=REPO=myorg/myrepo
```

Save and reload:

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker-github-watchdog
```

## Viewing logs

```bash
# Follow the watchdog log file
tail -f /var/log/docker-github-watchdog.log

# Or via journalctl
journalctl -u docker-github-watchdog -f
```

## Stop / Disable

```bash
sudo systemctl stop docker-github-watchdog
sudo systemctl disable docker-github-watchdog
```
