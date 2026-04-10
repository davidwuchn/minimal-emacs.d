---
title: Emacs Daemon Management - Complete Guide
status: active
category: knowledge
tags: [emacs, daemon, macos, linux, launchctl, systemctl, gptel, troubleshooting]
---

# Emacs Daemon Management - Complete Guide

A comprehensive guide to managing Emacs daemon across platforms, with focus on macOS launchctl and Linux systemd integration, theme management, single-daemon enforcement, and debugging best practices.

## Overview

Running Emacs as a daemon (`emacs --daemon`) provides near-instantaneous editor startup via `emacsclient`. However, daemon management introduces unique challenges:

- Platform-specific process management (launchctl vs systemctl)
- Theme/visual settings not automatically applied to new frames
- Cross-module function visibility in async callbacks
- Socket and port conflicts from multiple instances
- Retry logic failures from improper type checking

This guide synthesizes critical lessons learned from production deployments.

---

## Platform-Specific Daemon Management

### macOS: Use launchctl

The native macOS process management system for user-level agents.

| Command | Purpose |
|---------|---------|
| `launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist` | Start daemon |
| `launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist` | Stop daemon |
| `launchctl list \| grep emacs` | Check status |
| `launchctl start org.gnu.emacs.daemon` | Manual start |
| `launchctl stop org.gnu.emacs.daemon` | Manual stop |

**Recommended plist configuration:**

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
        <string>--daemon</string>
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

Place at: `~/Library/LaunchAgents/org.gnu.emacs.daemon.plist`

### Linux: Use systemctl --user

The proper way to manage user-level services on systemd-based systems.

```bash
systemctl --user start emacs    # Start daemon
systemctl --user stop emacs     # Stop daemon  
systemctl --user restart emacs  # Restart daemon
systemctl --user status emacs   # Check status
```

**Why systemctl instead of direct commands:**

| Direct Commands | systemctl --user |
|-----------------|------------------|
| Can timeout or hang | Proper timeout handling |
| May leave stale processes | Clean process lifecycle |
| No logging integration | Integrated with journald |
| Manual socket management | Automatic socket activation |

**Critical:** Never mix direct `emacs --daemon` with systemctl-managed instances. The socket file at `/run/user/1000/emacs/server` may already exist, causing conflicts.

---

## The Single Daemon Rule (CRITICAL)

### Why Only One Daemon?

Running multiple Emacs daemons causes:

- **Port conflicts**: Only one process can bind to the server socket
- **Client confusion**: `emacsclient` connects unpredictably
- **Resource waste**: Duplicate memory usage (~100MB+ each)
- **State inconsistency**: Buffers and worktrees get confused

### Single-Daemon Enforcement Script

**ALWAYS run this procedure before starting a daemon:**

```bash
#!/bin/bash
# Ensure only ONE Emacs daemon is running

echo "=== CHECKING FOR EXISTING DAEMONS ==="

# Count existing Emacs daemon processes
DAEMON_COUNT=$(pgrep -f "Emacs.*daemon" | wc -l)
echo "Found $DAEMON_COUNT Emacs daemon process(es)"

if [ "$DAEMON_COUNT" -gt 0 ]; then
    echo ""
    echo "Killing all existing Emacs processes..."
    pgrep -f "Emacs.*daemon" | while read pid; do
        echo 
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-X376j5.txt. Use Read tool if you need more]...