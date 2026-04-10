---
title: Emacs Daemon Management
status: active
category: knowledge
tags: [emacs, daemon, process-management, debugging, cross-platform]
---

# Emacs Daemon Management

## Overview

Emacs daemon mode (`emacs --daemon`) runs Emacs as a background server process, allowing rapid client connections via `emacsclient`. This document covers platform-specific daemon management, common anti-patterns, debugging techniques, and production-ready configurations.

## Starting and Stopping Daemons

### macOS: Using launchctl

The recommended approach for production daemon management on macOS:

```bash
# Check daemon status
launchctl list | grep emacs

# Start daemon
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Stop daemon
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Restart daemon
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist && \
  sleep 2 && \
  launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
```

**Launch Agent Plist Configuration:**

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

### Debian/Linux: Using systemctl --user

On Debian-based systems, use systemd user services:

```bash
# Start daemon
systemctl --user start emacs

# Stop daemon
systemctl --user stop emacs

# Restart daemon
systemctl --user restart emacs

# Check status
systemctl --user status emacs
```

**Important:** Always use `systemctl --user` instead of direct `emacs --daemon` commands. Direct commands can conflict with systemd-managed instances and cause socket file conflicts at `/run/user/<uid>/emacs/server`.

### Manual Daemon Management

For development and debugging, manual management provides better feedback:

```bash
# Start daemon manually
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 emacs --bg-daemon=copilot-auto-workflow

# Stop via emacsclient (may hang)
emacsclient --eval "(kill-emacs)"

# Use pkill for guaranteed termination
pkill -9 -f Emacs
```

## Single Daemon Enforcement

Running multiple Emacs daemons causes port conflicts, client confusion, and resource waste.

### Pre-Start Safety Check Script

```bash
#!/bin/bash
# Ensure only ONE Emacs daemon is running

echo "=== CHECKING FOR EXISTING DAEMONS ==="

DAEMON_COUNT=$(pgrep -f "Emacs.*daemon" | wc -l)
echo "Found $DAEMON_COUNT Emacs daemon process(es)"

if [ "$DAEMON_COUNT" -gt 0 ]; then
    echo "Killing all existing Emacs processes..."
    pgrep -f "Emacs.*daemon" | while read pid; do
        echo "  Killing PID: $pid"
        kill -9 $pid 2>/dev/null
    done
    
    sleep 3
    
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

# Unload from launchctl/systemd first
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist 2>/dev/null

# Start fresh
echo "Starting daemon..."
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
sleep 5

# Verify
NEW_COUNT=$(pgrep -f "Emacs.*daemon" | wc -l)
if [ "$NEW_COUNT" -eq 1 ]; then
    echo "✅ Single daemon running successfully"
    emacsclient -e "(+ 1 1)" 2>/dev/null && echo "✅ Daemon responsive"
else
    echo "❌ Expected 1 daemon, found $NEW_COUNT"
    exit 1
fi
```

### Quick Verification Commands

```bash
# Count daemons
pgrep -f "Emacs.*daemon" | wc -l

# Test client connection
emacsclient -e "(+ 1 1)"

# View daemon logs
tail -f /tmp/emacs-daemon.log
```

## Anti-Patterns

### Anti-Pattern 1: Stale Compiled Files

**Problem:** Compiled `.elc` files persist across daemon restarts, causing stale code to run.

**Symptoms:**
- Changes to `.el` files not reflected after daemon restart
- Debugging shows old code behavior
- Works in fresh Emacs but not in daemon

**Root Cause:** Emacs loads `.elc` if it exists, and restarting daemon doesn't recompile.

**Solution:**

```bash
# Remove all compiled files before restart
rm -f lisp/modules/*.elc

# Kill all Emacs processes
killall -9 Emacs

# Remove temp files
rm -rf /tmp/emacs*

# Start fresh daemon
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 emacs --bg-daemon=copilot-auto-workflow
```

**Prevention Options:**

| Option | Implementation | Use Case |
|--------|---------------|----------|
| Never compile | `;; -*- no-byte-compile: t; -*-` in file header | Development |
| Auto-recompile | `(setq load-prefer-newer t)` in early-init.el | Mixed workflows |
| Clean before restart | `find . -name "*.elc" -delete` in startup script | Production |

**Verification Test:**

```bash
rm -f lisp/modules/*.elc
emacs --batch -l lisp/modules/module.el -f some-function
```

### Anti-Pattern 2: Server Name Conflicts

**Problem:** Multiple cron jobs or scripts using the same Emacs daemon server name cause "already running" errors.

**Symptoms:**
- "Unable to start daemon: Emacs server named X already running"
- "failed to start worker daemon: X"
- Log files filled with daemon startup errors

**Root Cause:** Using same `SERVER_NAME` for different actions (e.g., researcher every 4h and auto-workflow at 10/14/18).

**Solution:**

```bash
# Use action-specific server names
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 emacs --bg-daemon=copilot-auto-workflow
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 emacs --bg-daemon=copilot-researcher
```

**Important:** The environment variable `MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1` does NOT prevent server name conflicts—it only allows multiple daemon instances with different names.

## Theme Management in Daemon Mode

### Problem

When running Emacs as a daemon, GUI-specific settings in `theme-setting.el` are not applied to new frames because:
- Daemon starts headless without display
- Theme settings apply during startup to non-existent frames
- New frames via `emacsclient -c` don't inherit these settings

### Best Solution: Reload Configuration

```elisp
(defun my/reload-theme-setting-for-frame (frame)
  "Reload theme-setting.el for FRAME to apply all visual settings."
  (when (display-graphic-p frame)
    (select-frame frame)
    (load-file "~/.emacs.d/lisp/theme-setting.el")))

(add-hook 'after-make-frame-functions #'my/reload-theme-setting-for-frame)
```

**Why This Works:**
- Uses `after-make-frame-functions` hook (triggers when new frames created)
- Checks `(display-graphic-p frame)` before applying (only GUI frames)
- Uses `load-file` not `require` (bypasses byte-compilation caching)
- `select-frame` ensures settings apply to correct frame

### Verification

```bash
# Create new themed frame
emacsclient -c -n

# Check background color applied
emacsclient -e "(face-attribute 'default :background)"
; Should return "#262626" or your theme's background
```

## Debugging Techniques

### 1. Syntax Check

```bash
emacs --batch --eval '
  (with-temp-buffer
    (insert-file-contents "lisp/modules/gptel-tools-agent.el")
    (goto-char (point-min))
    (condition-case nil
        (check-parens)
      (error (message "Syntax error"))))'
```

### 2. Count Parentheses

```python
#!/usr/bin/env python3
with open("lisp/modules/gptel-tools-agent.el", "r") as f:
    content = f.read()
print(f"Open: {content.count('(')}, Close: {content.count(')')}")
```

### 3. Find Exact Error Location

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

## Common Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Theme not loading in new frames | Daemon runs headless | Use `after-make-frame-functions` hook |
| "Server already running" | Multiple daemons or name conflict | Use unique server names, check with `pgrep` |
| Changes not reflected | Stale `.elc` files | Remove `.elc` files or set `load-prefer-newer` |
| emacsclient timeout | Using direct kill instead of systemctl | Use `systemctl --user restart emacs` |
| Socket file conflicts | systemd and direct commands conflict | Use only `systemctl --user` on Linux |

## Best Practices

1. **Platform-appropriate management:** Use `launchctl` on macOS, `systemctl --user` on Debian/Linux
2. **Single daemon rule:** Always verify only one daemon runs before starting
3. **Unique server names:** Use action-specific names (e.g., `copilot-auto-workflow` vs `copilot-researcher`)
4. **Clear before restart:** Remove stale `.elc` files when debugging code changes
5. **Test incrementally:** Don't make multiple complex changes at once
6. **Validate syntax:** Always check before committing or reloading
7. **Use systemd/launchctl:** Proper daemon management handles logging and crash recovery

## Related

- [Emacs Configuration] - Related to init file loading and theme-setting
- [Elisp Compilation] - Related to `.elc` byte-compilation behavior
- [Process Management] - General process control patterns
- [Emacs Server] - Server mode and emacsclient usage
- [Cross-Platform] - Platform-specific differences (macOS vs Linux)