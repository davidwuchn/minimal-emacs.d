---
title: Emacs Daemon Management
status: active
category: knowledge
tags: [emacs, daemon, macos, linux, launchctl, systemd, theme-loading]
---

# Emacs Daemon Management

This knowledge page covers Emacs daemon setup, management, and troubleshooting across macOS and Linux systems, with special attention to theme loading and single-instance enforcement.

## Overview

The Emacs daemon (`emacs --daemon`) allows you to run Emacs as a background server that accepts client connections via `emacsclient`. This provides near-instant startup times and preserves buffer state across sessions.

### Benefits

| Feature | Description |
|---------|-------------|
| Instant startup | New frames connect to running daemon, no initialization delay |
| State persistence | Buffers, registers, undo history survive restarts |
| Resource efficiency | Single process handles multiple frames |
| Remote editing | `emacsclient` works over SSH for remote editing |

---

## macOS Daemon Management (launchctl)

### Launch Agent vs Manual Management

- **Use `launchctl` for production/auto-start**: Native macOS process management, auto-starts on login, handles crashes with `KeepAlive`
- **Use manual commands for development**: Better error feedback during config testing and troubleshooting
- **Hybrid approach recommended**: launchctl for auto-start, manual for debugging

### Plist Configuration

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

### Essential Commands

```bash
# Check status
launchctl list | grep emacs
pgrep -f "Emacs.*daemon"

# Start daemon
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Stop daemon
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Restart daemon
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist && \
  sleep 2 && \
  launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Verify it's running
emacsclient -e "(+ 1 1)"  # Should return 2
```

---

## Linux/Debian Daemon Management (systemctl)

### Using systemctl --user

On Debian-based systems, use systemd user services to manage the Emacs daemon:

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

### Why systemctl?

- **Proper service management**: Systemd handles the lifecycle properly
- **Logging**: Access logs via `journalctl --user -u emacs`
- **Clean restart**: Avoids stale processes and socket conflicts
- **Timeout handling**: Direct `emacsclient --eval "(kill-emacs)"` can hang

---

## Theme Loading in Daemon Mode

### The Problem

When running Emacs as a daemon (`--daemon`), GUI-specific settings in your theme configuration are not applied to new frames because:
- Daemon starts headless without a display
- Theme settings are applied during startup to non-existent frames
- New frames created via `emacsclient -c` don't inherit these settings

### Best Solution: Reload Configuration File

Instead of duplicating theme logic, reload the entire configuration file when new GUI frames are created:

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
| Automatic consistency | Changes apply automatically to new frames |
| Complete coverage | Fonts, transparency, fullscreen, line numbers work |
| Maintainable | No duplicated code |
| Simple | One function handles everything |

### Implementation Notes

- Use `after-make-frame-functions` hook - triggers when new frames are created
- Always check `(display-graphic-p frame)` - only apply to GUI frames
- Use `load-file` not `require` - bypasses byte-compilation caching
- Use `select-frame` before loading - ensures settings apply to correct frame

### Verification

```bash
# Create new themed frame
emacsclient -c -n

# Check if background color applied
emacsclient -e "(face-attribute 'default :background)"
# Should return the theme's background color (e.g., "#262626")
```

---

## Single Daemon Enforcement (Critical)

### Why Single Daemon Matters

Running multiple Emacs daemons causes:
- **Port conflicts**: Only one daemon can bind to the server socket
- **Client confusion**: `emacsclient` connects to first available daemon
- **Resource waste**: Multiple daemons consume extra memory
- **State inconsistency**: Worktrees and buffers get confused between daemons

### Pre-Start Check Script

**ALWAYS run this procedure before starting daemon:**

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

# Unload from launchctl first (if loaded)
echo ""
echo "Unloading from launchctl..."
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist 2>/dev/null
sleep 2

# Start fresh daemon via launchctl
echo ""
echo "Starting daemon via launchctl..."
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Wait for startup
sleep 5

# Verify single daemon
NEW_COUNT=$(pgrep -f "Emacs.*daemon" | wc -l)
echo ""
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

### Quick Check Command

```bash
# Count daemons
pgrep -f "Emacs.*daemon" | wc -l

# If > 1, kill all and restart
if [ $(pgrep -f "Emacs.*daemon" | wc -l) -gt 1 ]; then
    pkill -9 -f Emacs
    sleep 3
    launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
    launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
fi
```

---

## Cross-Module Function Visibility

### Problem

Functions defined in one module (e.g., `gptel-tools-agent.el`) are not visible in async callbacks from other modules (e.g., `gptel-benchmark-subagent.el`).

### Solution A: require + declare-function

```elisp
;; In gptel-benchmark-subagent.el
(require 'gptel-tools-agent nil t)
(declare-function gptel-auto-workflow--read-file-contents "gptel-tools-agent")
```

### Solution B: Autoload Cookie

```elisp
;; In gptel-tools-agent.el
;;;###autoload
(defun gptel-auto-workflow--read-file-contents (filepath)
  "Read contents of FILEPATH and return as string."
  (with-temp-buffer
    (insert-file-contents filepath)
    (buffer-string)))
```

---

## Debugging Techniques

### 1. Check Syntax

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
tail -f /tmp/emacs-daemon.log
tail -f /tmp/emacs-daemon-error.log

# Linux/Debian
journalctl --user -u emacs -f
```

---

## Common Pitfalls and Solutions

### GUI Emacs vs Daemon Conflict

**Problem**: Running both GUI Emacs and daemon creates separate servers; emacsclient connects to whichever starts first.

**Solution**: Choose one approach - either GUI Emacs with server, or headless daemon with emacsclient frames. The recommended approach is daemon + `emacsclient -c` for fastest startup.

### Retry Logic Type Checking

**Problem**: Retry logic failing on nil or empty validation errors.

**Solution**: Add robust type checking:

```elisp
(if (and validation-error
         (stringp validation-error)           ; Ensure it's a string
         (> (length validation-error) 0)      ; Ensure not empty
         (string-match-p "error-pattern" validation-error)
         (not (bound-and-true-p gptel-auto-experiment--in-retry)))
    ;; Retry logic here
    ...)
```

### Function Definition Merge

**Problem**: Two function definitions accidentally merged together cause syntax errors.

**Broken:**
```elisp
(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)
(defun gptel-auto-workflow--read-file-contents (filepath)
  ...
  "Execute shell COMMAND..."  ;; ← Wrong docstring placement!
```

**Fixed:**
```elisp
(defun gptel-auto-workflow--read-file-contents (filepath)
  "Read contents of FILEPATH."
  (with-temp-buffer
    (insert-file-contents filepath)
    (buffer-string)))

(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)
  "Execute shell COMMAND with optional TIMEOUT."
  ...)
```

---

## Key Principles

1. **Simplicity over complexity** - Simple type checking > complex helper functions
2. **Declare dependencies** - Use `declare-function` for cross-module calls
3. **Test incrementally** - Don't make multiple complex changes at once
4. **Use native service managers** - launchctl on macOS, systemctl on Linux
5. **Validate syntax** - Always check before committing
6. **Single daemon rule** - ALWAYS ensure only one daemon runs
7. **Reload theme for frames** - Use `after-make-frame-functions` to apply themes to new GUI frames

---

## Related

- [Emacs Configuration](emacs-configuration) - General Emacs setup and configuration
- [Emacs Packages](emacs-packages) - Package management and installation
- [Emacs Lisp Development](emacs-lisp-development) - Writing Emacs Lisp code
- [Emacsclient Usage](emacsclient-usage) - Client connection options and flags