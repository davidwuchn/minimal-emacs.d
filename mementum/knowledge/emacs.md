---
title: Emacs Daemon Management and Development
status: active
category: knowledge
tags: [emacs, emacs-daemon, launchctl, systemctl, troubleshooting, elisp, development-workflow]
---

# Emacs Daemon Management and Development

## Overview

Emacs daemon mode runs a persistent Emacs server in the background, allowing `emacsclient` to create new frames instantly without the startup overhead of a full Emacs instance. This page consolidates critical lessons for managing Emacs daemon across platforms, debugging common issues, and maintaining a healthy development workflow.

## Platform-Specific Daemon Management

### macOS: Using launchctl

On macOS, the recommended approach for production daemon management is `launchctl` with a LaunchAgent plist file.

#### Plist Configuration

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

#### Essential launchctl Commands

| Command | Purpose |
|---------|---------|
| `launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist` | Start daemon |
| `launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist` | Stop daemon |
| `launchctl list \| grep emacs` | Check daemon status |
| `launchctl kickstart -kp gui/$(id -u)/org.gnu.emacs.daemon` | Force restart |

#### Log Monitoring

```bash
# Real-time log watching
tail -f /tmp/emacs-daemon.log
tail -f /tmp/emacs-daemon-error.log

# Check recent entries
tail -n 50 /tmp/emacs-daemon.log
```

### Linux/Debian: Using systemctl

On Linux systems with systemd, use user-level service management:

```bash
systemctl --user start emacs    # Start daemon
systemctl --user stop emacs     # Stop daemon
systemctl --user restart emacs  # Restart daemon
systemctl --user status emacs   # Check status
```

**Important:** Always use `systemctl --user` commands rather than direct `emacs --daemon` invocations to avoid conflicts with the systemd-managed service and stale socket files.

## Single Daemon Management (Critical)

### The Problem

Running multiple Emacs daemons causes:
- **Port conflicts**: Socket file at `/tmp/emacs$UID/` or `/run/user/$UID/emacs/server` can only be owned by one daemon
- **Client confusion**: `emacsclient` connects to whichever daemon claimed the socket first
- **Resource waste**: Multiple instances consume memory unnecessarily
- **State inconsistency**: Buffers and worktrees become confused across instances

### Safe Daemon Restart Script

Run this script before starting a daemon to ensure only one instance runs:

```bash
#!/bin/bash
# ensure-single-daemon.sh - Ensure only ONE Emacs daemon is running

set -e

echo "=== Checking for existing Emacs daemons ==="

# Count existing daemon processes
DAEMON_COUNT=$(pgrep -f "Emacs.*daemon" | wc -l)
echo "Found $DAEMON_COUNT Emacs daemon process(es)"

if [ "$DAEMON_COUNT" -gt 0 ]; then
    echo ""
    echo "Killing existing Emacs processes..."
    pgrep -f "Emacs.*daemon" | while read pid; do
        echo "  Killing PID: $pid"
        kill -9 "$pid" 2>/dev/null || true
    done
    
    # Wait for graceful termination
    sleep 3
    
    # Verify cleanup
    REMAINING=$(pgrep -f "Emacs.*daemon" | wc -l)
    if [ "$REMAINING" -eq 0 ]; then
        echo "✅ All Emacs processes terminated"
    else
        echo "⚠️  $REMAINING process(es) still running, forcing..."
        pkill -9 -f Emacs || true
        sleep 2
    fi
    
    # Clean up stale socket files
    rm -rf /tmp/emacs$(id -u)/
    rm -f /tmp/emacs*
fi

# On macOS, unload from launchctl first
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo ""
    echo "Unloading from launchctl..."
    launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist 2>/dev/null || true
    sleep 2
fi

# Start fresh daemon
echo ""
echo "Starting daemon..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
    sleep 5
else
    systemctl --user start emacs
    sleep 3
fi

# Verification
echo ""
echo "=== Verification ==="
NEW_COUNT=$(pgrep -f "Emacs.*daemon" | wc -l)
echo "Daemon processes: $NEW_COUNT"

if [ "$NEW_COUNT" -eq 1 ]; then
    echo "✅ Single daemon running successfully"
    if emacsclient -e "(+ 1 1)" 2>/dev/null; then
        echo "✅ Daemon is responsive"
    else
        echo "⚠️  Daemon not responding to emacsclient"
    fi
else
    echo "❌ Expected 1 daemon, found $NEW_COUNT"
    exit 1
fi
```

### Quick Verification Commands

```bash
# Count running daemons
pgrep -f "Emacs.*daemon" | wc -l

# If more than 1, force restart
if [ $(pgrep -f "Emacs.*daemon" | wc -l) -gt 1 ]; then
    pkill -9 -f Emacs && sleep 3
    # Then restart via launchctl or systemctl
fi

# Test client connection
emacsclient -e "(+ 1 1)"
```

## Theme Management in Daemon Mode

### The Problem

When running as a daemon, GUI-specific settings don't automatically apply to new frames because:
1. Daemon starts headless without a display
2. Theme settings in init files execute before any frame exists
3. New frames created via `emacsclient -c` don't inherit these initial settings

### Best Solution: Reload Configuration on Frame Creation

```elisp
(defun my/reload-theme-setting-for-frame (frame)
  "Reload theme-setting.el for FRAME to apply all visual settings."
  (when (display-graphic-p frame)
    (select-frame frame)
    (load-file (expand-file-name "lisp/theme-setting.el" user-emacs-directory))))

(add-hook 'after-make-frame-functions #'my/reload-theme-setting-for-frame)
```

### Why This Approach Wins

| Approach | Pros | Cons |
|----------|------|------|
| **Reload entire config file** | Single source of truth, automatic consistency, complete coverage | None significant |
| Duplicate settings in multiple places | Catches all settings | Code duplication, maintenance burden |
| Manually re-apply individual faces | Granular control | Time-consuming, error-prone |
| Complex conditional logic | Handles edge cases | Over-engineered, hard to maintain |

### Key Implementation Notes

- Use `after-make-frame-functions` hook (not `window-setup-hook` or similar)
- Always check `(display-graphic-p frame)` to avoid errors in terminal frames
- Use `select-frame` before loading to ensure settings target correct frame
- Use `load-file` not `require` to bypass byte-compilation caching

### Verification

```bash
# Create new themed frame
emacsclient -c -n

# Check theme applied
emacsclient -e "(face-attribute 'default :background)"
;; Should return theme background color, e.g., "#262626"
```

## Common Development Pitfalls

### 1. Merged Function Definitions

**Problem:** Two function definitions accidentally merged, causing syntax errors.

```elisp
;; BROKEN - two definitions merged:
(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)
(defun gptel-auto-workflow--read-file-contents (filepath)
  ...
  "Execute shell COMMAND..."  ;; ← Wrong docstring placement!
```

```elisp
;; FIXED - properly separated:
(defun gptel-auto-workflow--read-file-contents (filepath)
  "Read and return contents of FILEPATH."
  ...)

(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)
  "Execute shell COMMAND with TIMEOUT in seconds."
  ...)
```

### 2. Cross-Module Function Visibility

**Problem:** Function defined in one module not visible in async callbacks from another module.

**Solution A - Add declarations:**

```elisp
;; In gptel-benchmark-subagent.el
(require 'gptel-tools-agent nil t)
(declare-function gptel-auto-workflow--read-file-contents "gptel-tools-agent")
```

**Solution B - Add autoload cookie:**

```elisp
;; In gptel-tools-agent.el
;;;###autoload
(defun gptel-auto-workflow--read-file-contents (filepath)
  ...)
```

### 3. Type Checking in Retry Logic

**Problem:** Retry logic failing with `wrong-number-of-arguments` or void function errors when validation returns nil.

```elisp
;; ROBUST - proper type checking:
(when (and validation-error
            (stringp validation-error)           ; Ensure it's a string
            (> (length validation-error) 0)      ; Ensure not empty
            (string-match-p "error-pattern" validation-error)
            (not (bound-and-true-p gptel-auto-experiment--in-retry)))
  ;; Safe to proceed with retry
  ...)
```

### 4. Avoid Over-Engineering

**Anti-pattern:** Complex helper functions with symbol references and scope manipulation.

```elisp
;; AVOID - overly complex:
(defmacro my/with-retry (&rest body)
  `(let ((symbol (make-symbol "retry-count")))
     (set symbol 0)
     ...))

;; PREFER - simple inline logic with proper type checking
```

## Debugging Techniques

### Check for Syntax Errors

```bash
emacs --batch --eval '
  (with-temp-buffer
    (insert-file-contents "lisp/modules/gptel-tools-agent.el")
    (goto-char (point-min))
    (condition-case nil
        (check-parens)
      (error (message "Syntax error detected"))))'
```

### Count Parentheses

```bash
python3 << 'EOF'
with open("lisp/modules/gptel-tools-agent.el", "r") as f:
    content = f.read()
open_parens = content.count('(')
close_parens = content.count(')')
print(f"Open: {open_parens}, Close: {close_parens}")
if open_parens != close_parens:
    print(f"⚠️  MISMATCH: {open_parens - close_parens}")
else:
    print("✅ Balanced")
EOF
```

### Find Exact Error Location

```bash
emacs --batch --eval '
  (with-temp-buffer
    (insert-file-contents "file.el")
    (goto-char (point-min))
    (condition-case err
        (while t (forward-sexp))
      (scan-error 
       (message "Error at line %d, column %d" 
                (line-number-at-pos)
                (current-column)))))'
```

### Debug Async Callback Failures

```elisp
(defun my/debug-async-callback (result)
  "Debug async callback with detailed logging."
  (message "=== Callback Debug ===")
  (message "Result type: %s" (type-of result))
  (message "Result value: %S" result)
  (when (functionp 'gptel-auto-workflow--read-file-contents)
    (message "✅ Function is defined")
  (message "❌ Function NOT defined"))
```

## Process Conflicts: GUI vs Daemon

### The Issue

Running GUI Emacs alongside a daemon creates two separate servers:
- GUI Emacs with `(server-start)` creates its own server socket
- Daemon creates another server socket
- `emacsclient` connects to whichever starts first

### Resolution Matrix

| Scenario | Recommendation |
|----------|----------------|
| Primary use: daemon + emacsclient | Remove `(server-start)` from init, use daemon only |
| Need full GUI Emacs occasionally | Use `emacsclient -c` for new frames, not separate GUI instance |
| Development/debugging | Manual daemon start without launchctl for better error feedback |

### Best Practice

```bash
# Default: daemon + emacsclient
emacsclient -c .      # Open current directory in new frame
emacsclient -n FILE   # Open file without blocking terminal

# For debugging: direct instance
emacs --fg-daemon     # Run in foreground for error visibility
```

## Key Principles Summary

| Principle | Rationale |
|-----------|-----------|
| **Simplicity over complexity** | Simple type checking beats complex helper functions |
| **Declare dependencies explicitly** | Use `declare-function` for cross-module calls |
| **Test incrementally** | Don't make multiple complex changes at once |
| **Single daemon rule** | Always verify only one daemon is running |
| **Validate syntax before commit** | Use batch evaluation to catch errors early |
| **Platform-appropriate management** | launchctl on macOS, systemctl on Linux |
| **Single source of truth** | Keep theme settings in one file, reload on frame creation |

## Quick Reference Commands

### macOS

```bash
# Check status
launchctl list | grep emacs
pgrep -f "Emacs.*daemon" | wc -l

# Restart
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
sleep 2
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Force restart
pkill -9 -f Emacs && sleep 3 && launchctl load ...
```

### Linux

```bash
# Check status
systemctl --user status emacs
pgrep -f "Emacs.*daemon" | wc -l

# Restart
systemctl --user restart emacs
```

### Universal

```bash
# Test connection
emacsclient -e "(+ 1 1)"

# Create new frame
emacsclient -c -n

# Open file
emacsclient -n FILE

# View logs
tail -f /tmp/emacs-daemon.log
```

## Related

- [[Emacs Configuration Best Practices]]
- [[Elisp Development Workflow]]
- [[Emacs Client Configuration]]
- [[Cross-Module Dependencies in Elisp]]
- [[Async Processing in Emacs]]
```