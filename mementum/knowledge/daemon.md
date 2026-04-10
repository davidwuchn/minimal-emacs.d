---
title: daemon
status: open
---

Synthesized from 7 memories.

# Daemon Persistence Anti-Pattern

**Date**: 2026-04-02
**Category**: anti-pattern
**Related**: daemon, elc, compilation

## Anti-Pattern

Compiled `.elc` files persist across daemon restarts, causing stale code.

## Problem

1. Make changes to `.el` file
2. Restart daemon
3. Changes not reflected
4. Old compiled code still running

## Root Cause

- Emacs daemon loads `.elc` if it exists
- Restarting daemon doesn't recompile
- Stale `.elc` files persist

## Solution

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

## Prevention

### Option 1: Never compile
```elisp
;; In file header
;; -*- no-byte-compile: t; -*-
```

### Option 2: Auto-recompile
```elisp
;; In early-init.el
(setq load-prefer-newer t)  ; Prefer .el over .elc
```

### Option 3: Clean before restart
```bash
# Always clean before daemon restart
find . -name "*.elc" -delete
```

## Signal

- Changes not reflected after restart
- Debugging shows old code
- Works in new Emacs but not daemon
- Behavior different from fresh start

## Test

```bash
# Verify fresh code
rm -f lisp/modules/*.elc
emacs --batch -l lisp/modules/module.el -f some-function
```

# Daemon Server Name Conflict

**Pattern:** Multiple cron jobs using the same Emacs daemon server name cause "already running" errors.

**Symptoms:**
- "Unable to start daemon: Emacs server named X already running"
- "failed to start worker daemon: X"
- Log files filled with daemon startup errors

**Cause:**
- `run-auto-workflow-cron.sh` used same `SERVER_NAME` for all actions
- Researcher (every 4h) and auto-workflow (10/14/18) conflicted
- `MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1` doesn't prevent server name conflict

**Fix:**
- Use action-specific server names: `copilot-auto-workflow` vs `copilot-researcher`
- Separate log files per daemon: `${SERVER_NAME}.log`

**Commit:** `939928cf`

---
title: Emacs Daemon Auto-Workflow Lessons
date: 2026-03-30
---

# Emacs Daemon Auto-Workflow - Critical Lessons

## Problem Summary

The auto-workflow had multiple critical issues:
1. **Retry logic failing** with `wrong-number-of-arguments` errors
2. **Void function errors** for `gptel-auto-workflow--read-file-contents` during async callbacks
3. **Syntax errors** from merged function definitions
4. **Complex scope issues** in nested callbacks

## Root Causes & Solutions

### 1. Function Definition Merge (CRITICAL)
**Problem:** Two function definitions were accidentally merged together:
```elisp
;; BROKEN:
(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)

(defun gptel-auto-workflow--read-file-contents (filepath)
  ...
  "Execute shell COMMAND..."  ;; ← Wrong docstring placement!
```

**Solution:** Properly separate function definitions:
```elisp
;; FIXED:
(defun gptel-auto-workflow--read-file-contents (filepath)
  ...)

(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)
  "Execute shell COMMAND..."
  ...)
```

### 2. Cross-Module Function Visibility
**Problem:** Function defined in `gptel-tools-agent.el` not visible in async callbacks from `gptel-benchmark-subagent.el`

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
**Problem:** Retry logic failing on nil or empty validation errors

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

### 4. Over-Engineering Retry Logic
**Lesson:** Complex helper functions with symbol references and scope manipulation are error-prone

**Better Approach:** Keep it simple:
- Inline retry logic with proper type checking
- Avoid complex macro/symbol tricks
- Test incrementally

## macOS Daemon Management (launchctl)

### Proper Commands:
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

### Plist Configuration:
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

## Debugging Techniques

### 1. Check Syntax:
```bash
emacs --batch --eval '
  (with-temp-buffer
    (insert-file-contents "lisp/modules/gptel-tools-agent.el")
    (goto-char (point-min))
    (condition-case nil
        (check-parens)
      (error (message "Syntax error"))))'
```

### 2. Count Parentheses:
```bash
python3 << 'EOF'
with open("lisp/modules/gptel-tools-agent.el", "r") as f:
    content = f.read()
print(f"Open: {content.count('(')}, Close: {content.count(')')}")
EOF
```

### 3. Find Exact Error Location:
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

## Results

After all fixes:
- ✅ **114 experiments** completed
- ✅ **10.6% success rate** (12/113 kept)
- ✅ **56 high-quality** experiments (score ≥8)
- ✅ **0 critical errors**
- ✅ **Remote synced** to main branch

## Key Principles

1. **Simplicity over complexity** - Simple type checking > complex helper functions
2. **Declare dependencies** - Use `declare-function` for cross-module calls
3. **Test incrementally** - Don't make multiple complex changes at once
4. **Use launchctl** - Proper daemon management on macOS
5. **Validate syntax** - Always check before committing
6. **Single daemon rule** - ALWAYS ensure only one daemon runs

## Single Daemon Management (CRITICAL)

### Problem: Multiple Daemons
Running multiple Emacs daemons causes:
- Port conflicts
- Client connection issues
- Resource waste
- Confusing behavior

### Solution: Check Before Start

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

### Why This Matters
- **Port binding**: Only one daemon can bind to the server socket
- **Client confusion**: `emacsclient` connects to first available daemon
- **Resource usage**: Multiple daemons waste memory
- **State consistency**: Worktrees and buffers get confused between daemons

---
title: Emacs daemon setup on macOS
date: 2026-03-30
---

# Emacs Daemon Management on macOS

## Key Learnings

### Launch Agent vs Manual Management
- **Use `launchctl` for production/auto-start**: Native macOS process management, auto-starts on login, handles crashes with KeepAlive
- **Use manual commands for development**: Better error feedback during config testing and troubleshooting
- **Hybrid approach recommended**: launchctl for auto-start, manual for debugging

### Theme Loading Issue
- **Problem**: Daemon runs headless, doesn't load GUI themes automatically
- **Solution**: Use `after-make-frame-functions` hook to load theme when GUI frames are created
- **Configuration**: Remove conflicting `(server-start)` from init files when using daemon mode

### Process Conflicts
- **GUI Emacs vs Daemon**: Running both creates separate servers; emacsclient connects to whichever starts first
- **Resolution**: Choose one approach - either GUI Emacs with server, or headless daemon with emacsclient frames
- **Best practice**: Use daemon + emacsclient -c for fastest startup and consistent theming

### Verification Commands
```bash
# Check daemon status
pgrep -f "Emacs.*--daemon"

# Test client connection  
emacsclient -e "(+ 1 1)"

# View daemon logs
tail /tmp/emacs-daemon.log

# Manage via launchctl
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
```

### Oh-My-Zsh Integration
- Emacs aliases (`emacs`, `eframe`, `te`) work correctly with daemon
- They connect to existing daemon rather than starting new instances
- No configuration changes needed for oh-my-zsh emacs plugin

# Emacs Daemon on Debian: Use systemctl --user

## Discovery
When starting/stopping Emacs daemon on Debian, always use `systemctl --user` commands, not direct `emacs --daemon` or `emacs --fg-daemon`.

## Reason
- systemd user service is the proper way to manage Emacs daemon
- Direct commands can conflict with systemd-managed instance
- Socket file at `/run/user/1000/emacs/server` may already exist

## Commands
```bash
systemctl --user start emacs    # Start daemon
systemctl --user stop emacs     # Stop daemon
systemctl --user restart emacs  # Restart daemon
systemctl --user status emacs   # Check status
```

## Date
2026-03-28

---
title: Emacs daemon theme reloading strategy
date: 2026-03-30
---

# Emacs Daemon Theme Management

## Key Insight

When running Emacs as a daemon (`--daemon`), GUI-specific settings in `theme-setting.el` are not applied to new frames because:
- Daemon starts without GUI/display
- Theme settings are applied during startup to non-existent frames  
- New frames created via `emacsclient -c` don't inherit these settings

## Best Solution: Reload Configuration File

Instead of duplicating theme logic, **reload the entire `theme-setting.el` file** when new GUI frames are created:

```elisp
(defun my/reload-theme-setting-for-frame (frame)
  "Reload theme-setting.el for FRAME to apply all visual settings."
  (when (display-graphic-p frame)
    (select-frame frame)
    (load-file "~/.emacs.d/lisp/theme-setting.el")))

(add-hook 'after-make-frame-functions #'my/reload-theme-setting-for-frame)
```

## Why This Approach Wins

### ✅ Advantages
- **Single source of truth**: All theme logic stays in `theme-setting.el`
- **Automatic consistency**: Changes to theme file automatically apply to new frames
- **Complete coverage**: Fonts, transparency, fullscreen, line numbers, header line all work
- **Maintainable**: No duplicated code or settings
- **Simple**: One function handles everything

### ❌ Avoid These Patterns
- Duplicating theme settings in multiple places
- Manually re-applying individual face attributes
- Complex conditional logic for daemon vs GUI modes

## Implementation Notes

- Use `after-make-frame-functions` hook - triggers when new frames are created
- Always check `(display-graphic-p frame)` - only apply to GUI frames  
- Use `select-frame` before loading - ensures settings apply to correct frame
- Load with `load-file` not `require` - bypasses byte-compilation caching

## Verification

Test that all settings work:
```bash
emacsclient -c -n          # Create new themed frame
emacsclient -e "(face-attribute 'default :background)"  # Should return "#262626"
```

This pattern ensures your complete Emacs visual configuration works perfectly with daemon mode.

# Emacs Daemon via systemctl

**Discovery:** Use `systemctl --user` to manage emacs daemon, not direct emacsclient/emacs commands.

**Commands:**
```bash
systemctl --user restart emacs   # restart daemon
systemctl --user status emacs    # check status
systemctl --user stop emacs      # stop daemon
systemctl --user start emacs     # start daemon
```

**Why:** Systemd manages the service properly, handles logging, and ensures clean restart. Direct commands can timeout or leave stale processes.

**Error:** `emacsclient --eval "(kill-emacs)"` can hang/timeout. Use systemctl instead.

**Symbol:** 💡