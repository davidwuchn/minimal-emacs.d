---
title: Emacs Daemon
status: active
category: knowledge
tags: [emacs, daemon, emacsclient, launchctl, systemd, process-management]
---

# Emacs Daemon

The Emacs daemon (`emacs --daemon`) runs a headless Emacs server that can serve multiple client connections. This is essential for workflows requiring fast startup, remote access, and persistent state across sessions.

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
```

**launchd plist configuration** (`~/Library/LaunchAgents/org.gnu.emacs.daemon.plist`):

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

### Debian/Linux with systemd

Always use `systemctl --user` for daemon management:

```bash
# Start the daemon
systemctl --user start emacs

# Stop the daemon
systemctl --user stop emacs

# Restart the daemon
systemctl --user restart emacs

# Check status
systemctl --user status emacs
```

**Why not use direct commands?** Direct `emacs --daemon` can conflict with systemd-managed instances, causing socket file conflicts at `/run/user/1000/emacs/server`.

### Manual Development Mode

For debugging and development:

```bash
# Background daemon (preferred)
emacs --bg-daemon=copilot-auto-workflow

# Foreground daemon (for debugging)
emacs --fg-daemon
```

## Single Daemon Enforcement Pattern

Running multiple Emacs daemons causes port conflicts, client confusion, and resource waste. **Always enforce single daemon** before starting:

```bash
#!/bin/bash
# Ensure only ONE Emacs daemon is running

DAEMON_COUNT=$(pgrep -f "Emacs.*daemon" | wc -l)
echo "Found $DAEMON_COUNT Emacs daemon process(es)"

if [ "$DAEMON_COUNT" -gt 0 ]; then
    echo "Killing all existing Emacs processes..."
    pgrep -f "Emacs.*daemon" | while read pid; do
        kill -9 $pid 2>/dev/null
    done
    
    sleep 3
    
    # Clean up stale sockets
    rm -rf /tmp/emacs$(id -u)/
    rm -f /tmp/emacs*
fi

# Unload from launchctl/systemd first
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist 2>/dev/null

# Start fresh daemon
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
sleep 5

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

### Quick Verification Commands

```bash
# Count daemon processes
pgrep -f "Emacs.*daemon" | wc -l

# Test client connection
emacsclient -e "(+ 1 1)"

# View daemon logs
tail /tmp/emacs-daemon.log

# Check launchctl status
launchctl list | grep emacs
```

## Server Name Conflicts

### Problem

Multiple cron jobs or scripts using the **same server name** cause "already running" errors:

```
Unable to start daemon: Emacs server named X already running
failed to start worker daemon: X
```

### Solution: Action-Specific Server Names

Use unique server names per workflow:

| Workflow | Server Name | Log File |
|----------|-------------|----------|
| Auto-workflow | `copilot-auto-workflow` | `copilot-auto-workflow.log` |
| Researcher | `copilot-researcher` | `copilot-researcher.log` |
| Benchmark | `copilot-benchmark` | `copilot-benchmark.log` |

```bash
# Start with unique server name
emacs --bg-daemon=copilot-auto-workflow
emacs --bg-daemon=copilot-researcher
```

**Note:** The environment variable `MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1` does not prevent server name conflicts—it only allows multiple daemon instances.

## Daemon Persistence Anti-Pattern

### The Problem

Compiled `.elc` files persist across daemon restarts, causing stale code to run:

1. Make changes to `.el` file
2. Restart daemon
3. Changes not reflected
4. Old compiled code still running

### Root Cause

- Emacs daemon loads `.elc` if it exists
- Restarting daemon doesn't recompile
- Stale `.elc` files persist

### Solution: Clean Restart Procedure

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

**Option 1: Never compile**

```elisp
;; -*- no-byte-compile: t; -*-
```

**Option 2: Auto-recompile (prefer newer)**

```elisp
;; In early-init.el
(setq load-prefer-newer t)  ; Prefer .el over .elc
```

**Option 3: Clean before restart**

```bash
# Always clean before daemon restart
find . -name "*.elc" -delete
```

### Detection Signal

- Changes not reflected after restart
- Debugging shows old code
- Works in fresh Emacs but not daemon
- Behavior different from fresh start

### Verification Test

```bash
# Verify fresh code loads correctly
rm -f lisp/modules/*.elc
emacs --batch -l lisp/modules/module.el -f some-function
```

## Theme Management in Daemon Mode

### The Problem

When running as a daemon (`--daemon`):
- Daemon starts without GUI/display
- Theme settings applied during startup don't apply to new frames
- New frames created via `emacsclient -c` don't inherit visual settings

### Solution: Reload on Frame Creation

Use `after-make-frame-functions` to reload theme configuration:

```elisp
(defun my/reload-theme-setting-for-frame (frame)
  "Reload theme-setting.el for FRAME to apply all visual settings."
  (when (display-graphic-p frame)
    (select-frame frame)
    (load-file "~/.emacs.d/lisp/theme-setting.el")))

(add-hook 'after-make-frame-functions #'my/reload-theme-setting-for-frame)
```

### Why This Works

- **Single source of truth**: All theme logic stays in `theme-setting.el`
- **Automatic consistency**: Changes to theme file apply to new frames
- **Complete coverage**: Fonts, transparency, fullscreen, line numbers, header line
- **Maintainable**: No duplicated code

### Verification

```bash
# Create new themed frame
emacsclient -c -n

# Check background color applied
emacsclient -e "(face-attribute 'default :background)"
; Should return "#262626" or your theme's background
```

## Cross-Module Function Visibility

When defining functions in one module that are called from another (especially in async contexts):

### Problem

Function defined in `gptel-tools-agent.el` not visible in async callbacks from `gptel-benchmark-subagent.el`

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

### Check Syntax Errors

```bash
emacs --batch --eval '
  (with-temp-buffer
    (insert-file-contents "lisp/modules/gptel-tools-agent.el")
    (goto-char (point-min))
    (condition-case nil
        (check-parens)
      (error (message "Syntax error"))))'
```

### Count Parentheses

```bash
python3 << 'EOF'
with open("lisp/modules/gptel-tools-agent.el", "r") as f:
    content = f.read()
print(f"Open: {content.count('(')}, Close: {content.count(')')}")
EOF
```

### Find Exact Error Location

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

## Common Issues Summary

| Issue | Cause | Solution |
|-------|-------|----------|
| Changes not reflected | Stale `.elc` files | Delete `.elc` files before restart |
| "Server already running" | Same server name | Use unique server names |
| Theme not applied | Daemon headless | Use `after-make-frame-functions` |
| Client connection fails | Multiple daemons | Enforce single daemon |
| "Void function" error | Cross-module visibility | Use `require` or `declare-function` |
| systemd conflict | Direct commands vs systemctl | Use `systemctl --user` on Linux |

## Best Practices

1. **Single daemon rule**: Always ensure only one daemon runs per server name
2. **Platform-specific commands**: Use `launchctl` on macOS, `systemctl --user` on Linux
3. **Clean restart**: Remove `.elc` files before restarting after code changes
4. **Unique server names**: Different workflows = different server names
5. **Prefer systemctl/launchctl**: Don't use `emacsclient --eval "(kill-emacs)"`—it can hang
6. **Test incrementally**: Don't make multiple complex changes at once
7. **Verify after restart**: Always test client connection after daemon restart

## Related

- [Emacs Client Configuration](/emacs-client)
- [Launch Agents](/launch-agents)
- [Systemd User Services](/systemd)
- [Theme Configuration](/theme-configuration)
- [Process Management](/process-management)
- [Cron Job Integration](/cron-integration)