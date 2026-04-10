---
title: Emacs Daemon Management - Complete Guide
status: active
category: knowledge
tags: [emacs, daemon, elisp, macos, linux, debugging]
---

# Emacs Daemon Management - Complete Guide

This knowledge page covers comprehensive Emacs daemon setup, management, and troubleshooting across platforms. It synthesizes critical lessons learned from production use.

## Overview

The Emacs daemon (`emacs --daemon`) allows running Emacs as a background server, enabling quick client connections via `emacsclient`. This is essential for developers who want near-instantaneous editor startup while maintaining full IDE capabilities.

### Why Use Daemon Mode

| Benefit | Description |
|---------|-------------|
| Fast startup | `emacsclient -c` connects in milliseconds |
| Persistent state | Buffers, history, and environment survive restarts |
| Resource efficiency | Single Emacs process serves multiple frames |
| Remote editing | Connect via TRAMP to remote servers seamlessly |

---

## Platform-Specific Setup

### macOS: Launch Agent Management

For macOS, use `launchctl` for production daemon management. This provides native process lifecycle management with auto-start on login.

#### Creating the Launch Agent

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
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/emacs-daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/emacs-daemon-error.log</string>
</dict>
</plist>
```

#### Launchctl Commands

```bash
# Check daemon status
launchctl list | grep emacs
pgrep -f "Emacs.*daemon"

# Load (start) daemon - runs on login
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Unload (stop) daemon
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Restart daemon (unload + load with delay)
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist && \
  sleep 2 && \
  launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Verify daemon is responsive
emacsclient -e "(+ 1 1)"  # Returns 2 if working
```

### Linux (Debian/Ubuntu): Systemd User Service

On Linux, use `systemctl --user` to manage the Emacs daemon properly. This integrates with systemd for reliable process management.

```bash
# Start daemon
systemctl --user start emacs

# Stop daemon
systemctl --user stop emacs

# Restart daemon
systemctl --user restart emacs

# Check status
systemctl --user status emacs

# Verify daemon is responsive
emacsclient -e "(+ 1 1)"
```

### Why Use System Services Instead of Direct Commands

| Direct Command | Problem | System Service Solution |
|----------------|---------|------------------------|
| `emacs --daemon` | Can conflict with existing instance | Managed start/stop prevents conflicts |
| `emacsclient --eval "(kill-emacs)"` | Can hang/timeout | Clean service management |
| Manual process management | No auto-restart on crash | `KeepAlive` (macOS) / systemd auto-restart |

---

## Single Daemon Management (CRITICAL)

Running multiple Emacs daemons causes severe issues: port conflicts, client connection problems, resource waste, and confusing behavior. **Always ensure only one daemon runs.**

### Why Multiple Daemons Cause Problems

1. **Port binding**: Only one daemon can bind to the server socket at `/tmp/emacs$(id -u)/server`
2. **Client confusion**: `emacsclient` connects to whichever daemon starts first
3. **Resource waste**: Each daemon consumes significant memory
4. **State inconsistency**: Buffers and worktrees get confused between instances

### Safe Start Script

Use this script before starting the daemon:

```bash
#!/bin/bash
# ensure-single-emacs-daemon.sh
# Ensures only ONE Emacs daemon is running

echo "=== CHECKING FOR EXISTING DAEMONS ==="

# Count existing Emacs daemon processes
DAEMON_COUNT=$(pgrep -f "Emacs.*daemon" | wc -l)
echo "Found $DAEMON_COUNT Emacs daemon process(es)"

if [ "$DAEMON_COUNT" -gt 0 ]; then
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
echo "Unloading from launchctl..."
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist 2>/dev/null
sleep 2

# Start fresh daemon via launchctl (macOS)
echo "Starting daemon via launchctl..."
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Wait for startup
sleep 5

# Verify single daemon
NEW_COUNT=$(pgrep -f "Emacs.*daemon" | wc -l)
echo "=== VERIFICATION ==="
echo "Daemon processes: $NEW_COUNT"

if [ "$NEW_COUNT" -eq 1 ]; then
    echo "✅ Single daemon running successfully"
    emacsclient -e "(+ 1 1)" 2>/dev/null && echo "✅ Daemon responsive"
else
    echo "❌ Expected 1 daemon, found $NEW_COUNT"
    exit 1
fi
```

### Quick Check and Restart

```bash
# Count daemons
pgrep -f "Emacs.*daemon" | wc -l

# If > 1, kill all and restart
if [ $(pgrep -f "Emacs.*daemon" | wc -l) -gt 1 ]; then
    pkill -9 -f Emacs
    sleep 3
    # Then restart based on platform
    launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
    launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
    # OR on Linux:
    systemctl --user restart emacs
fi
```

---

## Theme Management in Daemon Mode

When running Emacs as a daemon, GUI themes don't load automatically because the daemon starts headless without a display.

### The Problem

1. Daemon starts without GUI/display
2. Theme settings in `theme-setting.el` apply during startup to non-existent frames
3. New frames created via `emacsclient -c` don't inherit visual settings (fonts, colors, transparency)

### Best Solution: Reload Configuration on Frame Creation

Use `after-make-frame-functions` hook to reload your theme configuration when new GUI frames are created:

```elisp
(defun my/reload-theme-setting-for-frame (frame)
  "Reload theme-setting.el for FRAME to apply all visual settings."
  (when (display-graphic-p frame)
    (select-frame frame)
    (load-file "~/.emacs.d/lisp/theme-setting.el")))

(add-hook 'after-make-frame-functions #'my/reload-theme-setting-for-frame)
```

### Why This Approach Wins

| Advantage | Description |
|-----------|-------------|
| Single source of truth | All theme logic stays in one file |
| Automatic consistency | Changes to theme file apply to all new frames automatically |
| Complete coverage | Fonts, transparency, fullscreen, line numbers, header line all work |
| Maintainable | No duplicated code across multiple places |
| Simple | One function handles everything |

### What NOT to Do

- ❌ Duplicating theme settings in multiple places
- ❌ Manually re-applying individual face attributes
- ❌ Complex conditional logic for daemon vs GUI modes

### Verification Commands

```bash
# Create new themed frame
emacsclient -c -n

# Verify background color is correct
emacsclient -e "(face-attribute 'default :background)"
# Should return something like "#262626"
```

---

## Common Pitfalls and Solutions

### 1. Function Definition Merge (CRITICAL)

**Problem:** Two function definitions accidentally merged, causing syntax errors:

```elisp
;; BROKEN:
(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)

(defun gptel-auto-workflow--read-file-contents (filepath)
  ...
  "Execute shell COMMAND..."  ;; ← Wrong docstring placement!)
```

**Solution:** Properly separate function definitions:

```elisp
;; FIXED:
(defun gptel-auto-workflow--read-file-contents (filepath)
  "Read FILEPATH and return contents."
  ...)

(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)
  "Execute shell COMMAND with optional TIMEOUT."
  ...)
```

### 2. Cross-Module Function Visibility

**Problem:** Function defined in one module not visible in another during async callbacks.

**Solution A:** Add `require` and `declare-function`:

```elisp
;; In gptel-benchmark-subagent.el
(require 'gptel-tools-agent nil t)
(declare-function gptel-auto-workflow--read-file-contents "gptel-tools-agent")
```

**Solution B:** Add autoload cookie:

```elisp
;; In gptel-tools-agent.el
;;;###autoload
(defun gptel-auto-workflow--read-file-contents (filepath)
  ...)
```

### 3. Validation Retry Type Checking

**Problem:** Retry logic fails on nil or empty validation errors.

**Solution:** Add robust type checking:

```elisp
(if (and validation-error
         (stringp validation-error)           ; ← Ensure it's a string
         (> (length validation-error) 0)      ; ← Ensure not empty
         (string-match-p "..." validation-error)
         (not (bound-and-true-p gptel-auto-experiment--in-retry)))
    ;; Retry logic
    ...)
```

### 4. GUI Emacs vs Daemon Conflicts

**Problem:** Running both GUI Emacs and daemon creates separate servers; `emacsclient` connects to whichever starts first.

**Solution:** Choose one approach - either GUI Emacs with server, or headless daemon with `emacsclient` frames. Best practice: use daemon + `emacsclient -c`.

### 5. Theme Not Loading in Daemon

**Problem:** Daemon runs headless, doesn't load GUI themes automatically.

**Solution:** Use `after-make-frame-functions` hook as shown above. Also remove conflicting `(server-start)` from init files when using daemon mode.

---

## Debugging Techniques

### 1. Check Syntax in Batch Mode

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

```bash
python3 << 'EOF'
with open("lisp/modules/gptel-tools-agent.el", "r") as f:
    content = f.read()
print(f"Open: {content.count('(')}, Close: {content.count(')')}")
EOF
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
       (message "Error at line %d" (line-number-at-pos))))))'
```

### 4. View Daemon Logs

```bash
# macOS
tail /tmp/emacs-daemon.log
tail /tmp/emacs-daemon-error.log

# Linux (systemd)
journalctl --user -u emacs -f
```

---

## Integration with Oh-My-Zsh

The Emacs aliases provided by oh-my-zsh (`emacs`, `eframe`, `te`) work correctly with daemon mode. They connect to the existing daemon rather than starting new instances. No configuration changes needed.

---

## Key Principles

1. **Simplicity over complexity** - Simple type checking is better than complex helper functions
2. **Declare dependencies** - Use `declare-function` for cross-module calls
3. **Test incrementally** - Don't make multiple complex changes at once
4. **Use platform services** - Use `launchctl` (macOS) or `systemctl` (Linux) for daemon management
5. **Validate syntax** - Always check for errors before committing code
6. **Single daemon rule** - ALWAYS ensure only one daemon runs
7. **Single source of truth** - Keep theme configuration in one file, reload on frame creation

---

## Related

- [Emacs Configuration] - Base configuration and init.el management
- [Emacsclient Usage] - Client options and frame management
- [Doom Emacs] - If using Doom, daemon management via `doom daemon`
- [Emacs TRAMP] - Remote editing with daemon mode
- [Emacs Packages] - Package management and loading order

---

## Quick Reference Commands

| Action | macOS | Linux |
|--------|-------|-------|
| Start | `launchctl load ...plist` | `systemctl --user start emacs` |
| Stop | `launchctl unload ...plist` | `systemctl --user stop emacs` |
| Restart | `launchctl unload && sleep 2 && load` | `systemctl --user restart emacs` |
| Status | `pgrep -f "Emacs.*daemon"` | `systemctl --user status emacs` |
| Test | `emacsclient -e "(+ 1 1)"` | `emacsclient -e "(+ 1 1)"` |