---
title: Emacs Daemon Management
status: active
category: knowledge
tags: [emacs, daemon, systemd, launchctl, process-management, anti-pattern]
---

# Emacs Daemon Management

## Overview

Emacs daemon mode runs a persistent Emacs server in the background, allowing `emacsclient` to open new frames instantly without the overhead of starting a full Emacs instance. This document covers essential patterns, anti-patterns, and platform-specific management strategies.

**Key benefits:**
- Instant frame creation (~100ms vs ~2-3s for full startup)
- Persistent state across editing sessions
- Shared kill ring, registers, and buffer history
- Centralized configuration management

## Quick Reference Commands

### Common Operations

| Operation | macOS | Linux/Debian | Universal |
|-----------|-------|--------------|-----------|
| Start | `launchctl load ...plis`t | `systemctl --user start emacs` | `emacs --daemon` |
| Stop | `launchctl unload ...plist` | `systemctl --user stop emacs` | `killall Emacs` |
| Restart | Combined unload/load | `systemctl --user restart emacs` | Kill + start |
| Status | `launchctl list \| grep emacs` | `systemctl --user status emacs` | `pgrep -f Emacs` |
| Test | `emacsclient -e "(+ 1 1)"` | Same | Same |

### Essential Diagnostics

```bash
# Check if daemon is running
pgrep -f "Emacs.*daemon" | wc -l

# Test client connection
emacsclient -e "(+ 1 1)"

# View server socket
ls -la /tmp/emacs*/server 2>/dev/null || echo "No server socket found"

# Count all Emacs processes
ps aux | grep -i emacs | grep -v grep
```

---

## Platform-Specific Management

### macOS: Using launchctl

**Launch Agents** are macOS's native mechanism for managing persistent processes. This is the recommended approach for production use.

#### Configuration File

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
        <string>--daemon</string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    
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

# Restart the daemon
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist && \
  sleep 2 && \
  launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Check status
launchctl list | grep emacs

# View logs
tail -f /tmp/emacs-daemon.log
tail -f /tmp/emacs-daemon-error.log
```

#### Why launchctl?

- **Auto-starts on login**: Set `RunAtLoad` to `true`
- **Handles crashes**: `KeepAlive` restarts the daemon if it exits unexpectedly
- **Native integration**: Proper cleanup and lifecycle management
- **Logging**: Captures stdout/stderr to files

### Linux/Debian: Using systemd --user

**systemd user services** provide proper daemon management on Linux systems.

#### Commands

```bash
# Start daemon
systemctl --user start emacs

# Stop daemon
systemctl --user stop emacs

# Restart daemon
systemctl --user restart emacs

# Check status
systemctl --user status emacs

# View logs
journalctl --user-unit=emacs
```

#### User Service Configuration

Create `~/.config/systemd/user/emacs.service`:

```ini
[Unit]
Description=Emacs Daemon
After=graphical.target

[Service]
Type=forking
ExecStart=/usr/bin/emacs --daemon
ExecStop=/usr/bin/emacsclient --eval "(kill-emacs)"
Restart=on-failure

[Install]
WantedBy=default.target
```

#### Why systemctl --user?

- **Proper lifecycle management**: Clean startup and shutdown
- **Logging integration**: Uses `journalctl` for centralized logs
- **Socket activation**: Optional socket-based activation
- **Dependency management**: Can specify service dependencies
- **No root required**: User-level services don't need sudo

---

## CRITICAL: Single Daemon Management

Running multiple Emacs daemons causes:
- Port/socket binding conflicts
- Client connection confusion
- Duplicate resource usage
- Inconsistent state between instances

### Guaranteed Single Daemon Script

**ALWAYS use this procedure before starting a daemon:**

```bash
#!/bin/bash
# ensure-single-daemon.sh - Guarantees only one Emacs daemon runs

echo "=== Checking for existing daemons ==="

# Count existing Emacs daemon processes
DAEMON_COUNT=$(pgrep -f "Emacs.*daemon" | wc -l)
echo "Found $DAEMON_COUNT Emacs daemon process(es)"

if [ "$DAEMON_COUNT" -gt 0 ]; then
    echo ""
    echo "Killing all existing Emacs processes..."
    pgrep -f "Emacs.*daemon" | while read pid; do
        echo "  Killing PID: $pid"
        kill -9 $pid 2>/dev/null
    done
    
    # Wait for termination
    sleep 3
    
    # Verify killed
    REMAINING=$(pgrep -f "Emacs.*daemon" | wc -l)
    if [ "$REMAINING" -eq 0 ]; then
        echo "✅ All Emacs processes killed"
    else
        echo "⚠️  $REMAINING process(es) still running, forcing..."
        pkill -9 -f Emacs
        sleep 2
    fi
    
    # Clean up stale sockets
    rm -rf /tmp/emacs$(id -u)/
    rm -f /tmp/emacs*
fi

# Unload from launchctl first (macOS)
echo ""
echo "Unloading from launchctl..."
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist 2>/dev/null
sleep 2

# Start fresh daemon via launchctl (macOS)
echo ""
echo "Starting daemon via launchctl..."
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Wait for startup
sleep 5

# Verify single daemon
NEW_COUNT=$(pgrep -f "Emacs.*daemon" | wc -l)
echo ""
echo "=== Verification ==="
echo "Daemon processes: $NEW_COUNT"

if [ "$NEW_COUNT" -eq 1 ]; then
    echo "✅ Single daemon running successfully"
    emacsclient -e "(+ 1 1)" 2>/dev/null && echo "✅ Daemon responsive"
else
    echo "❌ Expected 1 daemon, found $NEW_COUNT"
    exit 1
fi
```

### Quick Check & Fix

```bash
# If more than 1 daemon, kill all and restart
if [ $(pgrep -f "Emacs.*daemon" | wc -l) -gt 1 ]; then
    echo "Multiple daemons detected! Cleaning up..."
    pkill -9 -f Emacs
    sleep 3
    # Then restart with your preferred method
    launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
    launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
fi
```

### Why Single Daemon Matters

| Issue | Impact |
|-------|--------|
| Socket conflict | Only one daemon can bind to server socket |
| Client confusion | `emacsclient` connects to first available daemon |
| Memory waste | Each daemon loads full Emacs instance |
| State split | Buffers, kill ring, registers not shared |

---

## Persistence Anti-Pattern: Stale .elc Files

### The Problem

When you modify `.el` source files but changes don't take effect after daemon restart:

1. Make changes to `.el` file
2. Restart daemon
3. Changes not reflected
4. Old compiled `.elc` code still running

### Root Cause

- Emacs daemon loads `.elc` if it exists, skipping `.el`
- Restarting daemon doesn't trigger recompilation
- Stale `.elc` files persist in the filesystem

### Solution: Clean Slate Restart

```bash
# 1. Remove all compiled files in your lisp directory
rm -f lisp/modules/*.elc

# 2. Kill all Emacs processes
killall -9 Emacs

# 3. Remove temp files and stale sockets
rm -rf /tmp/emacs*
rm -rf ~/.emacs.d/auto-save-list/
rm -rf ~/.emacs.d/backups/

# 4. Start fresh daemon
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 emacs --daemon=my-server
```

### Prevention: Three Options

#### Option 1: Never Compile (Recommended for Development)

Add to the top of each `.el` file:

```elisp
;; -*- no-byte-compile: t; -*-
```

Or in your init file:

```elisp
(setq byte-compile-warnings '(not free-vars unresolved))
```

#### Option 2: Auto-Recompile (Best for Production)

In `early-init.el`:

```elisp
;; Prefer newer .el files over older .elc files
(setq load-prefer-newer t)
```

To force recompilation:

```bash
# Recompile all .el files
emacs --batch -eval "(byte-recompile-directory \".\" 0)"
```

#### Option 3: Clean Before Restart

```bash
# Always clean before daemon restart
find . -name "*.elc" -delete

# Or selectively
rm -f lisp/modules/*.elc
```

### Detection: Signs of Stale .elc

- Changes not reflected after restart
- Debugging shows old code behavior
- Works in fresh Emacs but not in daemon
- Behavior differs from `emacs --batch -l file.el`

### Verification Test

```bash
# Verify fresh code is loaded
rm -f lisp/modules/*.elc
emacs --batch -l lisp/modules/module.el -f some-function
```

---

## Server Name Conflicts

### Problem

Multiple cron jobs or scripts using the same Emacs daemon server name cause conflicts:

```
"Unable to start daemon: Emacs server named X already running"
"failed to start worker daemon: X"
```

### Root Cause

- Shared `SERVER_NAME` across different automated tasks
- `MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1` doesn't prevent server name conflicts
- Each daemon needs unique server name

### Solution: Action-Specific Server Names

```bash
# Use unique names per task
SERVER_NAME="copilot-auto-workflow" \
  emacs --daemon=copilot-auto-workflow

SERVER_NAME="copilot-researcher" \
  emacs --daemon=copilot-researcher

SERVER_NAME="copilot-benchmark" \
  emacs --daemon=copilot-benchmark
```

### Connect with Specific Server

```bash
# Connect to specific daemon
emacsclient -s copilot-auto-workflow -e "(+ 1 1)"

# vs generic connection (picks first available)
emacsclient -e "(+ 1 1)"
```

### Per-Server Logging

```bash
# Each daemon logs to its own file
SERVER_NAME="copilot-auto-workflow" \
  emacs --daemon=copilot-auto-workflow \
  --stderr="/tmp/emacs-auto-workflow.log"

SERVER_NAME="copilot-researcher" \
  emacs --daemon=copilot-researcher \
  --stderr="/tmp/emacs-researcher.log"
```

---

## Theme Management in Daemon Mode

### The Problem

When running Emacs as a daemon, GUI-specific settings in theme files don't apply to new frames because:
- Daemon starts headless without display
- Theme settings apply during startup to non-existent frames
- New frames via `emacsclient -c` don't inherit these settings

### Solution: Reload on Frame Creation

```elisp
(defun my/reload-theme-setting-for-frame (frame)
  "Reload theme-setting.el for FRAME to apply all visual settings."
  (when (display-graphic-p frame)
    (select-frame frame)
    (load-file "~/.emacs.d/lisp/theme-setting.el")))

(add-hook 'after-make-frame-functions #'my/reload-theme-setting-for-frame)
```

### Why This Approach Wins

| Approach | Pros | Cons |
|----------|------|------|
| Reload entire file | Single source of truth, complete coverage | May reload more than needed |
| Duplicated settings | Fine-grained control | Code duplication, maintenance burden |
| Manual face setting | Complete control | Tedious, error-prone |

### Verification

```bash
# Create new themed frame
emacsclient -c -n

# Verify theme loaded
emacsclient -e "(face-attribute 'default :background)"
; Should return "#262626" or your configured color
```

---

## Common Errors & Debugging

### Syntax Errors

#### Check Parentheses Balance

```bash
# Python one-liner
python3 << 'EOF'
with open("lisp/modules/gptel-tools-agent.el", "r") as f:
    content = f.read()
print(f"Open: {content.count('(')}, Close: {content.count(')')}")
EOF
```

#### Find Exact Error Location

```bash
emacs --batch --eval '
  (with-temp-buffer
    (insert-file-contents "file.el")
    (goto-char (point-min))
    (condition-case nil
        (while t (forward-sexp))
      (scan-error 
       (message "Error at line %d" (line-number-at-pos)))))'
```

#### Full Syntax Check

```bash
emacs --batch --eval '
  (with-temp-buffer
    (insert-file-contents "lisp/modules/gptel-tools-agent.el")
    (goto-char (point-min))
    (condition-case err
        (check-parens)
      (error (message "Syntax error: %s" err))))'
```

### Void Function Errors

**Problem:** Function defined in module A not visible in callbacks from module B

**Solution A: require + declare-function**

```elisp
;; In gptel-benchmark-subagent.el
(require 'gptel-tools-agent nil t)
(declare-function gptel-auto-workflow--read-file-contents "gptel-tools-agent")
```

**Solution B: Autoload cookie**

```elisp
;; In gptel-tools-agent.el
;;;###autoload
(defun gptel-auto-workflow--read-file-contents (filepath)
  ...)
```

### Wrong Number of Arguments

**Problem:** Retry logic failing with `wrong-number-of-arguments` errors

**Solution:** Add robust type checking

```elisp
(if (and validation-error
         (stringp validation-error)           ; Ensure it's a string
         (> (length validation-error) 0)      ; Ensure not empty
         (string-match-p "..." validation-error)
         (not (bound-and-true-p gptel-auto-experiment--in-retry)))
    ;; Safe to retry
    ...)
```

### Merge Function Definitions (Critical)

**Problem:** Accidentally merged function definitions

```elisp
;; BROKEN:
(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)

(defun gptel-auto-workflow--read-file-contents (filepath)
  ...
  "Execute shell COMMAND..."  ;; ← Wrong docstring!
```

**Solution:** Properly separate definitions

```elisp
;; FIXED:
(defun gptel-auto-workflow--read-file-contents (filepath)
  "Docstring for read-file-contents."
  ...)

(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)
  "Execute shell COMMAND..."
  ...)
```

---

## Anti-Patterns to Avoid

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Multiple daemons | Socket conflicts, state split | Use single daemon script |
| Stale .elc files | Changes not taking effect | Use `load-prefer-newer` or clean |
| Same server name | "already running" errors | Use unique per-task names |
| Complex retry macros | Scope issues, errors | Inline simple type checking |
| Duplicate theme settings | Maintenance burden | Reload entire file on frame creation |
| GUI + daemon both running | Confusing client connections | Choose one approach |

---

## Complete Daemon Workflow

### Fresh Start Checklist

```bash
#!/bin/bash
# fresh-daemon-start.sh - Complete fresh daemon startup

echo "=== FRESH EMACS DAEMON STARTUP ==="

# 1. Kill existing
echo "[1/7] Killing existing Emacs processes..."
pkill -9 -f Emacs 2>/dev/null
sleep 2

# 2. Clean temp files
echo "[2/7] Cleaning temp files..."
rm -rf /tmp/emacs*
rm -rf ~/.emacs.d/auto-save-list/

# 3. Clean compiled files (optional - for dev)
echo "[3/7] Cleaning .elc files..."
find ~/.emacs.d -name "*.elc" -delete 2>/dev/null

# 4. Clean sockets
echo "[4/7] Cleaning sockets..."
rm -f /tmp/emacs*/server

# 5. Unload from service manager
echo "[5/7] Unloading from service manager..."
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist 2>/dev/null
systemctl --user stop emacs 2>/dev/null

# 6. Wait for cleanup
echo "[6/7] Waiting for cleanup..."
sleep 2

# 7. Start fresh
echo "[7/7] Starting fresh daemon..."
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
# Or on Linux: systemctl --user start emacs

# Verify
sleep 3
if pgrep -f "Emacs.*daemon" | head -1 | xargs test -n 2>/dev/null; then
    echo "✅ Daemon running"
    emacsclient -e "(+ 1 1)" && echo "✅ Daemon responsive"
else
    echo "❌ Daemon failed to start"
    exit 1
fi
```

### Regular Maintenance

```bash
# Weekly cleanup script
#!/bin/bash

# Clean old compiled files
find ~/.emacs.d -name "*.elc" -mtime +7 -delete

# Clean backups
find ~/.emacs.d -name "*~" -mtime +30 -delete
find ~/.emacs.d -type d -name "backup*" -mtime +30 -exec rm -rf {} +

# Clean temp files
rm -rf /tmp/emacs*

# Restart daemon
pkill -HUP Emacs  # Graceful reload
```

---

## Related Topics

- [Emacs Client Configuration](/emacs-client) - Client flags, frame options, socket management
- [Compilation & Byte-Code](/compilation) - .elc file internals, recompilation strategies
- [Early Init Pattern](/early-init) - Startup optimization, load-prefer-newer
- [Systemd User Services](/systemd-user) - Linux service management deep dive
- [Launch Agents](/launch-agents) - macOS process management deep dive
- [Theme Configuration](/themes) - Theme loading in daemon/non-daemon modes