---
title: Emacs Daemon Management
status: active
category: knowledge
tags: [emacs, daemon, process-management, debugging, elisp]
---

# Emacs Daemon Management

This knowledge page covers the setup, management, troubleshooting, and best practices for running Emacs as a daemon on macOS and Linux systems.

## Overview

Running Emacs as a daemon (`emacs --daemon`) provides faster client startup times and persistent state across sessions. However, daemon mode introduces unique challenges around process management, configuration loading, and debugging that differ from interactive Emacs usage.

## Starting the Daemon

### macOS with launchctl

The recommended approach for production use on macOS:

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

### Linux with systemd

On Debian-based systems, use systemd user services:

```bash
# Manage daemon
systemctl --user start emacs    # Start daemon
systemctl --user stop emacs     # Stop daemon
systemctl --user restart emacs  # Restart daemon
systemctl --user status emacs   # Check status
```

### Manual Daemon Start (Development)

For development and debugging:

```bash
# Start as background daemon
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 emacs --bg-daemon=copilot-auto-workflow

# Start as foreground daemon (blocks terminal)
emacs --fg-daemon
```

## Single Daemon Enforcement Pattern

Running multiple Emacs daemons causes port conflicts, client connection issues, and resource waste. Always enforce a single daemon before starting:

```bash
#!/bin/bash
# ensure-single-daemon.sh - Ensure only ONE Emacs daemon is running

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

# Unload from launchctl/systemd first
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist 2>/dev/null
sleep 2

# Start fresh daemon
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
sleep 5

# Verify single daemon
NEW_COUNT=$(pgrep -f "Emacs.*daemon" | wc -l)
echo "Daemon processes: $NEW_COUNT"

if [ "$NEW_COUNT" -eq 1 ]; then
    echo "✅ Single daemon running successfully"
    emacsclient -e "(+ 1 1)" 2>/dev/null && echo "✅ Daemon responsive"
else
    echo "❌ Expected 1 daemon, found $NEW_COUNT"
    exit 1
fi
```

**Quick check command:**

```bash
# If > 1 daemon, kill all and restart
if [ $(pgrep -f "Emacs.*daemon" | wc -l) -gt 1 ]; then
    pkill -9 -f Emacs
    sleep 3
    launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
    launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
fi
```

## Server Name Conflicts

### Problem

Multiple cron jobs or scripts using the same Emacs daemon server name cause "already running" errors:

```
Unable to start daemon: Emacs server named X already running
failed to start worker daemon: X
```

### Solution: Action-Specific Server Names

Use unique server names per action:

| Action | Server Name | Log File |
|--------|-------------|----------|
| Auto-workflow | `copilot-auto-workflow` | `copilot-auto-workflow.log` |
| Researcher | `copilot-researcher` | `copilot-researcher.log` |

```bash
# Start with specific server name
emacs --daemon=copilot-auto-workflow

# Connect with matching server
emacsclient -s copilot-auto-workflow -c
```

**Important:** `MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1` does NOT prevent server name conflicts—it only allows multiple daemon processes with different names.

## Daemon Persistence Anti-Pattern

### Problem

Compiled `.elc` files persist across daemon restarts, causing stale code to run:

1. Make changes to `.el` file
2. Restart daemon
3. Changes not reflected
4. Old compiled code still running

### Root Cause

- Emacs daemon loads `.elc` if it exists
- Restarting daemon doesn't recompile
- Stale `.elc` files persist

### Solution: Clean Before Restart

```bash
# Remove all compiled files
rm -f lisp/modules/*.elc

# Kill all Emacs processes
killall -9 Emacs

# Remove temp files
rm -rf /tmp/emacs*

# Start fresh daemon
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 emacs --bg-daemon=copilot-auto-workflow
```

### Prevention Options

**Option 1: Never compile (file-level)**

```elisp
;; -*- no-byte-compile: t; -*-
```

**Option 2: Prefer newer files (early-init.el)**

```elisp
(setq load-prefer-newer t)  ; Prefer .el over .elc
```

**Option 3: Clean before restart**

```bash
# Always clean before daemon restart
find . -name "*.elc" -delete
```

### Detection Signs

- Changes not reflected after restart
- Debugging shows old code
- Works in new Emacs but not daemon
- Behavior different from fresh start

### Verification Test

```bash
# Verify fresh code loads
rm -f lisp/modules/*.elc
emacs --batch -l lisp/modules/module.el -f some-function
```

## Theme Loading in Daemon Mode

### Problem

When running Emacs as a daemon (`--daemon`), GUI-specific settings in `theme-setting.el` are not applied to new frames because:
- Daemon starts without GUI/display
- Theme settings are applied during startup to non-existent frames
- New frames created via `emacsclient -c` don't inherit these settings

### Solution: Reload Configuration for New Frames

```elisp
(defun my/reload-theme-setting-for-frame (frame)
  "Reload theme-setting.el for FRAME to apply all visual settings."
  (when (display-graphic-p frame)
    (select-frame frame)
    (load-file "~/.emacs.d/lisp/theme-setting.el")))

(add-hook 'after-make-frame-functions #'my/reload-theme-setting-for-frame)
```

**Why this approach works:**
- Single source of truth in `theme-setting.el`
- Automatic consistency when theme file changes
- Complete coverage: fonts, transparency, fullscreen, line numbers, header line
- Simple: one function handles everything

**Implementation notes:**
- Use `after-make-frame-functions` hook - triggers when new frames created
- Always check `(display-graphic-p frame)` - only apply to GUI frames
- Use `load-file` not `require` - bypasses byte-compilation caching

### Verification

```bash
# Create new themed frame
emacsclient -c -n

# Check background color applied
emacsclient -e "(face-attribute 'default :background)"
```

## Cross-Module Function Visibility

### Problem

Functions defined in one module (`gptel-tools-agent.el`) are not visible in async callbacks from another module (`gptel-benchmark-subagent.el`).

**Error:** `void-function gptel-auto-workflow--read-file-contents`

### Solution A: require + declare-function

```elisp
;; In gptel-benchmark-subagent.el
(require 'gptel-tools-agent nil t)
(declare-function gptel-auto-workflow--read-file-contents "gptel-tools-agent")
```

### Solution B: Autoload cookie

```elisp
;; In gptel-tools-agent.el
;;;###autoload
(defun gptel-auto-workflow--read-file-contents (filepath)
  ...)
```

## Debugging Techniques

### 1. Check Syntax with Emacs Batch

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
       (message "Error at line %d" (line-number-at-pos)))))'
```

### 4. Verify Daemon Logs

```bash
# macOS
tail /tmp/emacs-daemon.log
tail /tmp/emacs-daemon-error.log

# Linux (systemd)
journalctl --user -u emacs -f
```

### 5. Test Client Connection

```bash
# Basic test
emacsclient -e "(+ 1 1)"

# With specific server
emacsclient -s copilot-auto-workflow -e "(message \"connected\")"
```

## Common Issues Reference

| Issue | Symptom | Solution |
|-------|---------|----------|
| Server name conflict | "Emacs server named X already running" | Use unique server names per action |
| Stale code | Changes not reflected after restart | Delete `.elc` files before restart |
| Theme not loading | Visual settings missing in new frames | Use `after-make-frame-functions` hook |
| Void function | Function not defined in async callback | Add `require` or `declare-function` |
| Multiple daemons | Port conflicts, strange behavior | Enforce single daemon before start |
| launchctl failure | Daemon won't start | Check plist syntax, verify path |
| systemd conflict | Socket file already exists | Use `systemctl --user` commands |

## Best Practices Summary

1. **Single daemon rule**: Always ensure only one daemon runs
2. **Unique server names**: Use action-specific names (e.g., `copilot-auto-workflow` vs `copilot-researcher`)
3. **Clean before restart**: Remove `.elc` files or set `load-prefer-newer`
4. **Use proper management tools**: launchctl on macOS, systemctl on Linux
5. **Test incrementally**: Don't make multiple complex changes at once
6. **Declare dependencies**: Use `declare-function` for cross-module calls
7. **Validate syntax**: Always check before committing
8. **Simplify retry logic**: Inline type checking > complex helper functions

## Related

- [Emacs Configuration](emacs-configuration)
- [Elisp Development](elisp-development)
- [Process Management](process-management)
- [Launch Agents](launch-agents)
- [Systemd Services](systemd-services)
- [Emacsclient Usage](emacsclient-usage)
- [Cross-Module Dependencies](cross-module-dependencies)