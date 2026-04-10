---
title: Emacs Daemon Management - Complete Guide
status: active
category: knowledge
tags: [emacs, daemon, emacsclient, launchctl, systemd, macos, debian, themes]
---

# Emacs Daemon Management - Complete Guide

This knowledge page covers Emacs daemon setup, management, and troubleshooting across different operating systems, with emphasis on common pitfalls and battle-tested solutions.

## Overview

Running Emacs as a daemon provides significant benefits:
- **Fast startup**: Instant frame creation via `emacsclient`
- **Resource efficiency**: Single process serves multiple clients
- **State persistence**: Buffers, history, and state survive client disconnections

However, daemon mode introduces unique challenges around theme loading, process management, and cross-module function visibility.

---

## macOS Daemon Management with launchctl

### Why launchctl?

- Native macOS process management
- Auto-starts on login via LaunchAgents
- Handles crashes with `KeepAlive`
- Proper logging to files

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

| Action | Command |
|--------|---------|
| Check status | `launchctl list \| grep emacs` |
| Start daemon | `launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist` |
| Stop daemon | `launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist` |
| Restart daemon | `launchctl unload ... && sleep 2 && launchctl load ...` |

### Manual Commands (Development/Troubleshooting)

```bash
# Check daemon status
pgrep -f "Emacs.*--daemon"

# Test client connection  
emacsclient -e "(+ 1 1)"

# View daemon logs
tail -f /tmp/emacs-daemon.log
```

---

## Debian/Systemd Management

### Why systemctl --user?

- Proper service management via systemd
- Handles logging automatically
- Ensures clean restart without stale processes
- Manages socket activation

### Commands

| Action | Command |
|--------|---------|
| Start | `systemctl --user start emacs` |
| Stop | `systemctl --user stop emacs` |
| Restart | `systemctl --user restart emacs` |
| Status | `systemctl --user status emacs` |

### Why Not Direct Commands?

Direct `emacs --daemon` or `emacs --fg-daemon` commands can:
- Conflict with systemd-managed instance
- Leave stale socket files at `/run/user/1000/emacs/server`
- Cause timeout issues with `emacsclient --eval "(kill-emacs)"`

**Always prefer `systemctl --user` for daemon management on Debian.**

---

## Single Daemon Rule (CRITICAL)

### The Problem

Running multiple Emacs daemons causes:
- Port/socket conflicts
- Client connection issues
- Resource waste
- Confusing behavior with state inconsistency

### Check Before Start Script

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
        echo "⚠️  Forcing cleanup..."
        pkill -9 -f Emacs
        sleep 2
    fi
    
    rm -rf /tmp/emacs$(id -u)/
    rm -f /tmp/emacs*
fi

# Unload from launchctl first (macOS)
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist 2>/dev/null
sleep 2

# Start fresh daemon via launchctl (macOS)
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
sleep 5

NEW_COUNT=$(pgrep -f "Emacs.*daemon" | wc -l)

if [ "$NEW_COUNT" -eq 1 ]; then
    echo "✅ Single daemon running successfully"
    emacsclient -e "(+ 1 1)" 2>/dev/null && echo "✅ Daemon responsive"
else
    echo "❌ Expected 1 daemon, found $NEW_COUNT"
    exit 1
fi
```

### Quick Verification

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

## Theme Loading in Daemon Mode

### The Problem

When running Emacs as a daemon:
- Daemon starts headless (no GUI/display)
- Theme settings apply during startup to non-existent frames
- New frames via `emacsclient -c` don't inherit visual settings

### Solution: Reload Configuration on Frame Creation

```elisp
(defun my/reload-theme-setting-for-frame (frame)
  "Reload theme-setting.el for FRAME to apply all visual settings."
  (when (display-graphic-p frame)
    (select-frame frame)
    (load-file "~/.emacs.d/lisp/theme-setting.el")))

(add-hook 'after-make-frame-functions #'my/reload-theme-setting-for-frame)
```

### Why This Works

| Approach | Pros | Cons |
|----------|------|------|
| Duplicate settings | Complete control | Code duplication, drift |
| Manual face changes | Granular control | Brittle, incomplete |
| **Reload config file** | Single source of truth | Requires proper file structure |

### Implementation Notes

- **Hook**: Use `after-make-frame-functions` — triggers when new frames are created
- **Guard**: Always check `(display-graphic-p frame)` — only apply to GUI frames
- **Select**: Use `select-frame` before loading — ensures settings apply to correct frame
- **Load method**: Use `load-file` not `require` — bypasses byte-compilation caching

### Verification

```bash
# Create new themed frame
emacsclient -c -n

# Check background color applied
emacsclient -e "(face-attribute 'default :background)"
# Should return "#262626" or your configured value
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
       (message "Error at line %d" (line-number-at-pos)))))'
```

### 4. Common Error Patterns

| Error | Cause | Fix |
|-------|-------|-----|
| `wrong-number-of-arguments` | Merged function definitions | Separate with proper closing parens |
| `void-function` | Cross-module visibility | Add `require` or `declare-function` |
| `invalid-function` | Syntax error in definition | Run syntax check |
| Client timeout | No daemon running | Start daemon, check status |

---

## Cross-Module Function Visibility

### The Problem

Functions defined in one module aren't visible in async callbacks from another module:

```elisp
;; gptel-tools-agent.el
(defun gptel-auto-workflow--read-file-contents (filepath)
  ...)
```

```elisp
;; gptel-benchmark-subagent.el - FAILS
(async-start
 (lambda () (gptel-auto-workflow--read-file-contents "file.txt")))
```

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
  ...)
```

### When to Use Each

| Method | Use Case |
|--------|----------|
| `require` | Module always needed, load at startup |
| `declare-function` | Function exists, delay loading |
| `;;;###autoload` | Public API, dynamic loading needed |

---

## Retry Logic Best Practices

### Type Checking Pattern

Always validate before operating on return values:

```elisp
(if (and validation-error
         (stringp validation-error)           ; Ensure it's a string
         (> (length validation-error) 0)      ; Ensure not empty
         (string-match-p "error-pattern" validation-error)
         (not (bound-and-true-p gptel-auto-experiment--in-retry)))
    ;; Retry logic
    ...)
```

### Lesson: Simplicity Wins

Avoid complex helper functions with symbol references and scope manipulation. Instead:
- Inline retry logic with proper type checking
- Test incrementally
- Avoid macro tricks

---

## Common Issues Summary

| Issue | Platform | Solution |
|-------|----------|----------|
| Theme not loading | macOS/Debian | Use `after-make-frame-functions` hook |
| Multiple daemons | Both | Run check script before starting |
| Connection timeout | Both | Verify daemon running, check socket |
| Cross-module errors | Both | Use `require` + `declare-function` |
| GUI vs daemon conflict | macOS | Choose one approach, use daemon + emacsclient |
| Stale socket files | Debian | Use systemctl, not direct commands |

---

## Key Principles

1. **Single daemon rule**: ALWAYS ensure only one daemon runs
2. **Prefer native tools**: launchctl on macOS, systemctl on Debian
3. **Test incrementally**: Don't make multiple complex changes at once
4. **Declare dependencies**: Use `require` and `declare-function` for cross-module calls
5. **Validate syntax**: Always check parens before committing
6. **Simplify retry logic**: Type checking > complex helper functions
7. **Theme reloading**: Reload config file, not duplicate settings
8. **Verify after changes**: Test with `emacsclient -e` commands

---

## Related

- [Emacs Configuration Management](config-management)
- [Emacs Lisp Development](elisp-development)
- [Emacs Client Setup](emacsclient-setup)
- [Theme Configuration](theme-configuration)
- [Systemd User Services](systemd-user-services)
- [macOS LaunchAgents](launchagents)
- [Async Elisp Programming](async-elisp)
- [Emacs Performance Optimization](performance)

---

## References

- Emacs Manual: [Emacs Server](https://www.gnu.org/software/emacs/manual/html_node/emacs/Emacs-Server.html)
- Emacs Manual: [Init File](https://www.gnu.org/software/emacs/manual/html_node/emacs/Init-File.html)
- macOS Developer: [LaunchServices](https://developer.apple.com/documentation/servicemanagement)
- Debian Wiki: [systemd/User](https://wiki.debian.org/systemd/User)