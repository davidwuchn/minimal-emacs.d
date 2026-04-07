---
title: Emacs Daemon Management
status: active
category: knowledge
tags: [emacs, daemon, systemd, launchctl, anti-pattern]
---

# Emacs Daemon Management

## Overview

The Emacs daemon (`emacs --daemon`) runs Emacs as a persistent server process, allowing instant frame creation via `emacsclient`. This document synthesizes critical lessons for managing daemons across platforms, avoiding common pitfalls, and handling edge cases.

## Platform-Specific Management

### Linux (systemd)

On Debian and other systemd-based distributions, **always use `systemctl --user`** for daemon management:

```bash
# Essential commands
systemctl --user start emacs      # Start daemon
systemctl --user stop emacs       # Stop daemon
systemctl --user restart emacs    # Restart daemon
systemctl --user status emacs     # Check status and recent logs
```

**Why not direct commands?**
- systemd already manages the server socket at `/run/user/UID/emacs/server`
- Direct `emacs --daemon` commands conflict with the systemd-managed instance
- systemctl handles logging, crash recovery, and clean restarts

**Error to avoid:**
```bash
# DON'T do this - causes conflicts
emacsclient --eval "(kill-emacs)"  # Can hang/timeout

# DO this instead
systemctl --user restart emacs
```

### macOS (launchctl)

Use `launchctl` with a Launch Agent for production, manual commands for development:

#### Launch Agent Setup

Create `~/Library/LaunchAgents/org.gnu.emacs.daemon.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>org.gnu.emacs.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/Emacs.app/Contents/MacOS/Emacs</string>
        <string>--daemon=main</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/emacs-daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/emacs-daemon-error.log</string>
</dict>
</plist>
```

#### launchctl Commands

```bash
# Load (start) the daemon
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Unload (stop) the daemon
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Restart with delay
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist && \
  sleep 2 && \
  launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Check status
launchctl list | grep emacs
```

#### When to Use Each Approach

| Scenario | Recommended Method |
|----------|-------------------|
| Auto-start on login | launchctl Launch Agent |
| Production server | launchctl or systemd |
| Development/debugging | Manual `emacs --daemon` |
| Testing configuration | Manual (better error feedback) |
| CI/CD pipelines | Direct commands with timeout |

## Single Daemon Rule

**CRITICAL:** Only one Emacs daemon should run per user. Multiple daemons cause:

- Port/socket binding conflicts
- `emacsclient` connects unpredictably
- Duplicate resource usage
- State inconsistency across frames

### Pre-Start Checklist

Run this script before starting any daemon:

```bash
#!/bin/bash
set -euo pipefail

echo "=== Ensuring Single Emacs Daemon ==="

# Kill existing daemons
for pid in $(pgrep -f "Emacs.*daemon" 2>/dev/null); do
    echo "Killing PID $pid..."
    kill -9 "$pid" 2>/dev/null || true
done

sleep 3

# Verify
if [ $(pgrep -f "Emacs.*daemon" | wc -l) -gt 0 ]; then
    echo "Warning: Daemons still running, forcing..."
    pkill -9 -f Emacs
    sleep 2
fi

# Clean stale sockets
rm -rf /tmp/emacs$(id -u)/ 2>/dev/null || true
rm -f /tmp/emacs* 2>/dev/null || true

# Unload launchctl if present
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist 2>/dev/null || true

echo "✅ Ready to sta
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-RbbU4W.txt. Use Read tool if you need more]...