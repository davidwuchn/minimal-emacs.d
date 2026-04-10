---
title: Emacs Daemon Management
status: active
category: knowledge
tags: [emacs, daemon, systemd, launchctl, process-management]
---

# Emacs Daemon Management

This knowledge page covers the Emacs daemon, process management across platforms, common pitfalls, and best practices for reliable daemon operations.

## What is an Emacs Daemon?

An Emacs daemon is a background Emacs instance that runs without a graphical frame, allowing `emacsclient` to connect to it quickly without loading the full Emacs initialization each time. This significantly reduces startup latency for repeated tasks.

## Starting and Stopping Daemons

### macOS with launchctl

```bash
# Create a Launch Agent plist at ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
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

### Linux (Debian/Ubuntu) with systemd

```bash
# Always use systemctl --user, not direct emacs --daemon
systemctl --user start emacs    # Start daemon
systemctl --user stop emacs     # Stop daemon
systemctl --user restart emacs  # Restart daemon
systemctl --user status emacs   # Check status
```

| Command | Purpose |
|---------|---------|
| `systemctl --user start emacs` | Start the daemon |
| `systemctl --user stop emacs` | Stop the daemon |
| `systemctl --user restart emacs` | Restart (stop + start) |
| `systemctl --user status emacs` | Check running state |

**Why systemd?**: Direct `emacs --daemon` commands can conflict with systemd-managed instances, causing socket conflicts at `/run/user/1000/emacs/server`.

### Manual Development Mode

For development and troubleshooting, use manual commands:

```bash
# Start daemon manually
emacs --daemon=my-server

# Start in background mode (preferred for scripts)
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 emacs --bg-daemon=copilot-auto-workflow

# Connect to daemon
emacsclient -e "(+ 1 1)"

# Stop daemon gracefully
emacsclient --eval "(kill-emacs)"
```

**Note**: The `MINIMAL_EMACS_ALLOW_SECOND_DAEMON` variable only allows a second daemon process to start—it does NOT prevent server name conflicts. Always use unique server names.

## Common Problems and Solutions

### Problem 1: Server Name Conflicts

**Symptoms**:
- "Unable to start daemon: Emacs server named X already running"
- "failed to start worker daemon: X"
- Log files filled with daemon startup errors

**Cause**: Multiple cron jobs or scripts using the same server name.

**Solution**: Use action-specific server names.

```bash
# BAD: Same name for different actions
SERVER_NAME="copilot"  # Used by both researcher and auto-workflow

# GOOD: Unique names per action
SERVER_NAME="copilot-auto-workflow"   # For automated tasks (10am, 2pm, 6pm)
SERVER_NAME="copilot-researcher"      # For research tasks (every 4h)
```

```bash
# Verify which daemon is running
pgrep -af "Emacs.*daemon"

# List all server names
ls -la /tmp/emacs*/server 2>/dev/null || echo "No servers found"
```

### Problem 2: Persistence Anti-Pattern (.elc files)

**Symptoms**:
- Changes to `.el` files not reflected after daemon restart
- Debugging shows old code
- Works in fresh Emacs but not in daemon
- Behavior differs from fresh start

**Root Cause**: Emacs loads `.elc` (byte-compiled) files if they exist, bypassing `.el` changes.

**Complete Cleanup Procedure**:

```bash
# Step 1: Remove all compiled files in your lisp directory
rm -f lisp/modules/*.elc

# Step 2: Kill all Emacs processes
killall -9 Emacs 2>/dev/null
pkill -9 -f Emacs 2>/dev/null

# Step 3: Remove temp files and stale sockets
rm -rf /tmp/emacs*
rm -rf /run/user/$(id -u)/emacs/

# Step 4: Start fresh daemon
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 emacs --bg-daemon=my-server
```

**Prevention Options**:

| Option | Code | When to Use |
|--------|------|--------------|
| Never compile | `;; -*- no-byte-compile: t; -*-` at file top | For development files |
| Prefer newer | `(setq load-prefer-newer t)` in early-init.el | General development |
| Clean before restart | `find . -name "*.elc" -delete` in scripts | CI/automation |

```elisp
;; In early-init.el - prefer .el over .elc
(setq load-prefer-newer t)
```

```elisp
;; At the top of development files
;; -*- no-byte-compile: t; -*-
```

### Problem 3: Multiple Daemons

**Symptoms**:
- Port conflicts
- Client connection issues
- Confusing behavior
- Resource waste

**Solution**: Always ensure only one daemon runs.

**Complete Single-Daemon Script**:

```bash
#!/bin/bash
# ensure-single-daemon.sh - Ensure only ONE Emacs daemon runs

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

# Start fresh daemon
echo ""
echo "Starting daemon..."
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
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

**Quick Check Command**:

```bash
# If more than 1 daemon, kill all and restart
if [ $(pgrep -f "Emacs.*daemon" | wc -l) -gt 1 ]; then
    pkill -9 -f Emacs
    sleep 3
    launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist 2>/dev/null
    launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
fi
```

## Theme Management in Daemon Mode

When running Emacs as a daemon, GUI-specific settings in `theme-setting.el` are not applied to new frames because the daemon starts headless without a display.

### Solution: Reload on Frame Creation

```elisp
(defun my/reload-theme-setting-for-frame (frame)
  "Reload theme-setting.el for FRAME to apply all visual settings."
  (when (display-graphic-p frame)
    (select-frame frame)
    (load-file "~/.emacs.d/lisp/theme-setting.el")))

(add-hook 'after-make-frame-functions #'my/reload-theme-setting-for-frame)
```

**Why this works**:
- `after-make-frame-functions` triggers when new GUI frames are created via `emacsclient -c`
- `display-graphic-p` ensures settings only apply to graphical frames
- `select-frame` ensures settings apply to the correct frame
- `load-file` bypasses byte-compilation caching

**Verification**:

```bash
# Create new themed frame
emacsclient -c -n

# Check background color applied
emacsclient -e "(face-attribute 'default :background)"
; Should return "#262626" (or your theme's background)
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

### Verify Fresh Code Loads

```bash
rm -f lisp/modules/*.elc
emacs --batch -l lisp/modules/module.el -f some-function
```

### Common Log Locations

| Platform | Log Path |
|----------|----------|
| macOS (launchctl) | `/tmp/emacs-daemon.log`, `/tmp/emacs-daemon-error.log` |
| Linux (systemd) | `journalctl --user -u emacs` |
| Manual | stderr of the emacs process |

## Platform Comparison

| Feature | macOS (launchctl) | Linux (systemd) |
|---------|-------------------|-----------------|
| Auto-start on boot | ✅ Via plist RunAtLoad | ✅ Via user service |
| Crash recovery | ✅ KeepAlive=true | ✅ Restart=always |
| Log management | Manual file monitoring | journalctl |
| Best for | Production daemons | Production daemons |
| Manual mode | Good for debugging | Good for debugging |

## Best Practices Summary

1. **Single daemon rule**: ALWAYS ensure only one daemon runs
2. **Unique server names**: Use action-specific names (e.g., `copilot-auto-workflow` vs `copilot-researcher`)
3. **Use proper tooling**: `launchctl` on macOS, `systemctl --user` on Linux
4. **Clean before restart**: Remove `.elc` files when debugging code changes
5. **Platform-specific commands**: Don't mix manual and service management
6. **Test with `emacs --batch`**: Verify code loads without daemon overhead
7. **Theme reload hook**: Use `after-make-frame-functions` for daemon theme settings

## Related

- [Emacs Configuration](configuration) - Related to init file management
- [Emacsclient Usage](emacsclient) - Client connection patterns
- [Launchctl](launchctl) - macOS process management
- [Systemd](systemd) - Linux service management
- [Byte Compilation](byte-compilation) - Understanding .elc files

---

**Last Updated**: 2026-04-02  
**Status**: active