---
title: Emacs Daemon Management
status: active
category: knowledge
tags: [emacs, daemon, workflow, troubleshooting, macOS, linux]
---

# Emacs Daemon Management

This knowledge page covers the essential patterns, anti-patterns, and best practices for managing Emacs as a persistent daemon across different platforms.

## Overview

Emacs daemon mode runs Emacs as a background server process, allowing instant client connections via `emacsclient`. This is essential for automation workflows, AI integrations, and rapid development iteration.

## Starting and Stopping the Daemon

### macOS (launchctl)

```bash
# Check status
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

### Debian/Linux (systemctl)

```bash
systemctl --user start emacs    # Start daemon
systemctl --user stop emacs     # Stop daemon
systemctl --user restart emacs  # Restart daemon
systemctl --user status emacs   # Check status
```

### Manual/Development Mode

```bash
# Start daemon manually
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 emacs --bg-daemon=copilot-auto-workflow

# Or traditional daemon
emacs --daemon

# Stop daemon via client (may hang, prefer systemctl)
emacsclient --eval "(kill-emacs)"

# Kill all Emacs processes
pkill -9 -f Emacs
```

## Single Daemon Management (CRITICAL)

Running multiple Emacs daemons causes port conflicts, client connection issues, and resource waste. **ALWAYS ensure only one daemon runs.**

### Pre-Start Check Script

```bash
#!/bin/bash
# Ensure only ONE Emacs daemon is running

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
    
    sleep 3
    
    # Clean up stale sockets
    rm -rf /tmp/emacs$(id -u)/
    rm -f /tmp/emacs*
fi

# Start fresh daemon
emacs --daemon

# Verify single daemon
NEW_COUNT=$(pgrep -f "Emacs.*daemon" | wc -l)
if [ "$NEW_COUNT" -eq 1 ]; then
    echo "✅ Single daemon running successfully"
    emacsclient -e "(+ 1 1)" && echo "✅ Daemon responsive"
else
    echo "❌ Expected 1 daemon, found $NEW_COUNT"
    exit 1
fi
```

### Quick Check Commands

```bash
# Count daemons
pgrep -f "Emacs.*daemon" | wc -l

# If > 1, kill all and restart
if [ $(pgrep -f "Emacs.*daemon" | wc -l) -gt 1 ]; then
    pkill -9 -f Emacs
    sleep 3
    emacs --daemon
fi
```

## Server Name Management

Multiple cron jobs using the same Emacs daemon server name cause "already running" errors.

### The Problem

```
"Unable to start daemon: Emacs server named X already running"
"failed to start worker daemon: X"
```

### Solution: Use Action-Specific Server Names

| Action | Server Name | Log File |
|--------|-------------|----------|
| Auto-workflow | `copilot-auto-workflow` | `copilot-auto-workflow.log` |
| Researcher | `copilot-researcher` | `copilot-researcher.log` |

```bash
# Start with explicit server name
emacs --daemon=copilot-auto-workflow

# Connect to specific server
emacsclient -s copilot-auto-workflow -e "(+ 1 1)"
```

## Theme Reloading in Daemon Mode

Daemon runs headless, so GUI theme settings don't apply to new frames created via `emacsclient -c`.

### Best Solution: Reload Configuration File

```elisp
(defun my/reload-theme-setting-for-frame (frame)
  "Reload theme-setting.el for FRAME to apply all visual settings."
  (when (display-graphic-p frame)
    (select-frame frame)
    (load-file "~/.emacs.d/lisp/theme-setting.el")))

(add-hook 'after-make-frame-functions #'my/reload-theme-setting-for-frame)
```

### Why This Works

- Uses `after-make-frame-functions` hook - triggers when new frames are created
- Checks `(display-graphic-p frame)` - only applies to GUI frames
- Uses `load-file` not `require` - bypasses byte-compilation caching
- Single source of truth - all theme logic stays in `theme-setting.el`

## Daemon Persistence Anti-Pattern

Compiled `.elc` files persist across daemon restarts, causing stale code to run.

### Symptoms

- Changes not reflected after restart
- Debugging shows old code
- Works in fresh Emacs but not daemon
- Behavior different from fresh start

### Root Cause

1. Make changes to `.el` file
2. Restart daemon
3. Emacs loads existing `.elc` instead of `.el`
4. Stale compiled code runs

### Prevention Options

**Option 1: Never compile (header comment)**

```elisp
;; -*- no-byte-compile: t; -*-
```

**Option 2: Auto-recompile (early-init.el)**

```elisp
(setq load-prefer-newer t)  ; Prefer .el over .elc
```

**Option 3: Clean before restart**

```bash
find . -name "*.elc" -delete
```

### Full Clean Procedure

```bash
# Remove all compiled files
rm -f lisp/modules/*.elc

# Kill all Emacs processes
killall -9 Emacs

# Remove temp files
rm -rf /tmp/emacs*

# Start fresh daemon
emacs --daemon
```

### Test Fresh Code

```bash
rm -f lisp/modules/*.elc
emacs --batch -l lisp/modules/module.el -f some-function
```

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

```python
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

## Common Pitfalls and Solutions

### Cross-Module Function Visibility

**Problem**: Function defined in one module not visible in async callbacks from another.

**Solution A**: Add `require` and `declare-function`

```elisp
;; In gptel-benchmark-subagent.el
(require 'gptel-tools-agent nil t)
(declare-function gptel-auto-workflow--read-file-contents "gptel-tools-agent")
```

**Solution B**: Add autoload cookie

```elisp
;; In gptel-tools-agent.el
;;;###autoload
(defun gptel-auto-workflow--read-file-contents (filepath)
  ...)
```

### Validation Retry Type Checking

**Problem**: Retry logic failing on nil or empty validation errors.

**Solution**: Add robust type checking

```elisp
(if (and validation-error
         (stringp validation-error)           ; Ensure it's a string
         (> (length validation-error) 0)      ; Ensure not empty
         (string-match-p "error-pattern" validation-error)
         (not (bound-and-true-p gptel-auto-experiment--in-retry)))
    ;; Retry logic
    ...)
```

### Function Definition Merge

**Problem**: Two function definitions accidentally merged together.

```elisp
;; BROKEN:
(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)
(defun gptel-auto-workflow--read-file-contents (filepath)
  ...
  "Execute shell COMMAND..."  ;; ← Wrong docstring placement!
```

**Solution**: Properly separate definitions

```elisp
;; FIXED:
(defun gptel-auto-workflow--read-file-contents (filepath)
  ...)

(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)
  "Execute shell COMMAND..."
  ...)
```

## Platform-Specific Notes

### macOS Launch Agent Configuration

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

### GUI Emacs vs Daemon

Running both creates separate servers. Choose one approach:
- **Daemon + emacsclient -c**: Fastest startup, consistent theming
- **GUI Emacs with server**: Better for interactive use

## Verification Commands

```bash
# Check daemon status
pgrep -f "Emacs.*daemon"

# Test client connection
emacsclient -e "(+ 1 1)"

# View daemon logs
tail /tmp/emacs-daemon.log

# Count running instances
pgrep -f "Emacs.*daemon" | wc -l
```

## Key Principles

1. **Single daemon rule**: ALWAYS ensure only one daemon runs
2. **Platform-appropriate management**: Use launchctl on macOS, systemctl on Debian
3. **Clean before restart**: Remove `.elc` files when debugging stale code
4. **Declare dependencies**: Use `declare-function` for cross-module calls
5. **Test incrementally**: Don't make multiple complex changes at once
6. **Validate syntax**: Always check before committing
7. **Simple over complex**: Simple type checking beats complex helper functions

## Related

- [[elc-compilation]] - Byte-compilation and .elc file handling
- [[emacsclient]] - Client connections to daemon
- [[theme-configuration]] - Theme management in Emacs
- [[launchctl]] - macOS process management
- [[systemd]] - Linux process management
- [[troubleshooting]] - General debugging patterns