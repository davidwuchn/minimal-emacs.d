---
title: Emacs Daemon Management
status: active
category: knowledge
tags: [emacs, daemon, launchctl, systemd, macos, linux, theme]
---

# Emacs Daemon Management

## Overview

The Emacs daemon mode (`emacs --daemon`) allows running Emacs as a background server, enabling fast client connections via `emacsclient`. This document covers daemon setup, management, theme handling, and critical development patterns discovered through extensive实践经验.

## macOS Daemon Setup with launchctl

### Why launchctl?

- **Native process management**: macOS's official process supervisor
- **Auto-start on login**: `RunAtLoad` and `KeepAlive` keys
- **Crash recovery**: Automatically restarts crashed daemon
- **Clean shutdown**: Proper graceful termination

### Launch Agent Plist Configuration

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

### Essential launchctl Commands

| Operation | Command |
|-----------|---------|
| Check status | `launchctl list \| grep emacs` |
| Start daemon | `launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist` |
| Stop daemon | `launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist` |
| Restart daemon | `launchctl unload ... && sleep 2 && launchctl load ...` |

### Development vs Production Strategy

| Context | Approach | Rationale |
|---------|----------|-----------|
| Production | launchctl | Auto-starts, handles crashes, proper logging |
| Development | Manual commands | Better error feedback during config testing |
| Debugging | Manual after fixing issues | Real-time output visibility |

**Recommendation**: Use launchctl for auto-start, manual `emacs --daemon` for troubleshooting.

---

## Linux/Debian Daemon Setup with systemd

### Why systemd?

- **Proper service management**: Handles PID tracking, logging, restart policies
- **Socket activation**: Can start daemon on-demand via socket
- **Clean conflict prevention**: Prevents duplicate daemon issues
- **Standardized interface**: Consistent commands across distributions

### systemd User Service Commands

```bash
# Start daemon
systemctl --user start emacs

# Stop daemon  
systemctl --user stop emacs

# Restart daemon
systemctl --user restart emacs

# Check status
systemctl --user status emacs

# Enable auto-start on login
systemctl --user enable emacs
```

### systemd Service File

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
WantedBy=multi-user.target
```

### Important Notes

- Always use `systemctl --user` (not `sudo systemctl`)
- Don't mix direct `emacs --daemon` with systemd-managed instances
- Socket file at `/run/user/1000/emacs/server` may already exist from prior runs

---

## THE SINGLE DAEMON RULE (CRITICAL)

This is the most important rule: **ONLY ONE Emacs daemon should ever run**.

### Problems with Multiple Daemons

| Symptom | Cause |
|---------|-------|
| Port/socket conflicts | Only one daemon can bind to server socket |
| Client connection issues | `emacsclient` connects to first available daemon |
| Resource waste | Each daemon consumes ~100-200MB RAM |
| State inconsistency | Buffers and worktrees confuse between instances |
| Strange behavior | Unpredictable which daemon handles requests |

### Before Starting Daemon: Check Procedure

**ALWAYS run this before starting the daemon:**

```bash
#!/bin/bash
# ensure-single-daemon.sh - Run before starting Emacs daemon

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
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist 2>/dev/null
sleep 2

# Start fresh daemon
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
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

### Quick Check and Fix

```bash
# Quick check
pgrep -f "Emacs.*daemon" | wc -l

# If > 1, kill all and restart
if [ $(pgrep -f "Emacs.*daemon" | wc -l) -gt 1 ]; then
    pkill -9 -f Emacs
    sleep 3
    # For macOS
    launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
    launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
    # For Linux
    systemctl --user restart emacs
fi
```

---

## Theme Management in Daemon Mode

### The Problem

When running Emacs as a daemon (`--daemon`):
- Daemon starts headless without a display
- GUI theme settings apply during startup to non-existent frames
- New frames created via `emacsclient -c` don't inherit these settings

### The Solution: Reload on Frame Creation

Use `after-make-frame-functions` hook to reload theme configuration:

```elisp
(defun my/reload-theme-setting-for-frame (frame)
  "Reload theme-setting.el for FRAME to apply all visual settings."
  (when (display-graphic-p frame)
    (select-frame frame)
    (load-file "~/.emacs.d/lisp/theme-setting.el")))

(add-hook 'after-make-frame-functions #'my/reload-theme-setting-for-frame)
```

### Why This Approach Wins

| Advantage | Explanation |
|-----------|--------------|
| Single source of truth | All theme logic stays in one file |
| Automatic consistency | Changes to theme file automatically apply |
| Complete coverage | Fonts, transparency, fullscreen, line numbers, header line |
| Maintainable | No duplicated code or settings |
| Simple | One function handles everything |

### What Gets Applied

This pattern ensures these settings work in daemon mode:
- Font configuration
- Window transparency
- Fullscreen mode
- Line numbers
- Header line
- All face customizations

### Verification Commands

```bash
# Create new themed frame
emacsclient -c -n

# Verify background color
emacsclient -e "(face-attribute 'default :background)"
; Should return "#262626" or your theme color
```

---

## Cross-Module Development Patterns

### The Problem: Function Visibility in Async Contexts

When developing modular Emacs packages, functions defined in one module may not be visible in async callbacks from another module:

```
gptel-tools-agent.el defines function
       ↓
gptel-benchmark-subagent.el calls it in async callback
       ↓
void-function error at runtime
```

### Solution A: require + declare-function

In the calling module:

```elisp
;; In gptel-benchmark-subagent.el
(require 'gptel-tools-agent nil t)
(declare-function gptel-auto-workflow--read-file-contents "gptel-tools-agent")
```

### Solution B: Autoload Cookie

In the defining module:

```elisp
;; In gptel-tools-agent.el
;;;###autoload
(defun gptel-auto-workflow--read-file-contents (filepath)
  ...)
```

### Function Definition Merging: A Critical Bug

**Problem**: Accidentally merging two function definitions causes silent failures:

```elisp
;; BROKEN - docstring in wrong place!
(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)

(defun gptel-auto-workflow--read-file-contents (filepath)
  ...
  "Execute shell COMMAND..."  ;; ← Wrong docstring placement!
```

**Fixed**:

```elisp
(defun gptel-auto-workflow--read-file-contents (filepath)
  "Read contents of FILEPATH and return as string."
  ...)

(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)
  "Execute shell COMMAND with optional TIMEOUT in seconds."
  ...)
```

### Type Checking in Retry Logic

Robust type checking prevents cryptic errors:

```elisp
(if (and validation-error
         (stringp validation-error)           ; Ensure it's a string
         (> (length validation-error) 0)      ; Ensure not empty
         (string-match-p "..." validation-error)
         (not (bound-and-true-p gptel-auto-experiment--in-retry)))
    ;; Retry logic
    ...)
```

### Principle: Simplicity Over Complexity

| Pattern | Result |
|---------|--------|
| Complex helper functions with symbol references | Error-prone, hard to debug |
| Inline retry with proper type checking | Reliable, testable |
| Macro tricks for scope manipulation | Difficult to maintain |

**Lesson**: Keep retry logic simple with proper type guards rather than complex helper functions.

---

## Debugging Techniques

### 1. Check for Syntax Errors

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

### 4. Test Daemon Responsiveness

```bash
# Basic test
emacsclient -e "(+ 1 1)"

# Check theme
emacsclient -e "(face-attribute 'default :background)"

# View logs
tail -f /tmp/emacs-daemon.log
tail -f /tmp/emacs-daemon-error.log
```

---

## Common Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Theme not loading in new frames | Daemon started headless | Use `after-make-frame-functions` hook |
| Client connects to wrong daemon | Multiple daemons running | Kill extras, use single daemon rule |
| `emacsclient` hangs | No daemon running or socket stale | Start daemon or check socket |
| Theme conflicts | Multiple theme loading | Unload conflicting themes before loading |
| Cross-module void function | Missing require/declare | Add `require` and `declare-function` |
| Retry logic fails | Type checking on nil | Add proper `(stringp ...)`, `(> (length ...) 0)` checks |

---

## GUI Emacs vs Daemon: Process Conflicts

### The Problem

Running both GUI Emacs and daemon creates:
- Two separate servers
- `emacsclient` connects to whichever starts first
- Theme settings applied inconsistently
- Resource duplication

### Resolution

Choose one approach:

| Approach | Command | Best For |
|----------|---------|----------|
| Daemon + client | `emacs --daemon` then `emacsclient -c` | Fastest startup, consistent theming |
| GUI Emacs + server | GUI Emacs with `(server-start)` | Interactive development |

**Best Practice**: Use daemon + emacsclient for maximum speed and consistent theme loading.

---

## Oh-My-Zsh Integration

The oh-my-zsh emacs plugin works correctly with daemon mode:

```bash
emacs        # Opens in existing daemon frame
eframe       # New frame via emacsclient -c
te           # Terminal emacsclient -t
```

No configuration changes needed - aliases automatically connect to existing daemon.

---

## Summary Checklist

- [ ] Use `launchctl` (macOS) or `systemctl --user` (Linux) for daemon management
- [ ] ALWAYS check for existing daemons before starting new one
- [ ] Use `after-make-frame-functions` for theme reloading
- [ ] Add `require` and `declare-function` for cross-module calls
- [ ] Use autoload cookies for public functions
- [ ] Keep retry logic simple with proper type checking
- [ ] Test incrementally - don't make multiple complex changes at once
- [ ] Verify syntax before committing code
- [ ] Choose daemon OR GUI server, not both

---

## Related

- [Emacs Configuration](emacs-configuration)
- [Emacs Package Development](emacs-package-development)
- [Emacs Lisp Best Practices](emacs-lisp-best-practices)
- [Emacsclient Usage](emacsclient-usage)
- [Emacs Performance Optimization](emacs-performance-optimization)
- [Emacs Theme Configuration](emacs-theme-configuration)
- [Systemd User Services](systemd-user-services)
- [launchd macOS Services](launchd-macos-services)