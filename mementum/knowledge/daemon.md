---
title: Emacs Daemon Management
status: active
category: knowledge
tags: [emacs, daemon, emacsclient, launchctl, systemd, process-management]
---

# Emacs Daemon Management

The Emacs daemon (`emacs --daemon`) runs a headless Emacs server that can accept connections from `emacsclient`. This provides faster startup times and shared state across editing sessions. However, daemon mode introduces unique challenges around process management, configuration loading, and theme application.

## Starting the Daemon

### macOS via launchctl (Recommended for Production)

Create a launch agent plist at `~/Library/LaunchAgents/org.gnu.emacs.daemon.plist`:

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

Then manage with launchctl:

```bash
# Start daemon
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Stop daemon
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Restart daemon
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist && \
  sleep 2 && \
  launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
```

### Debian/Linux via systemctl (Recommended)

Create `~/.config/systemd/user/emacs.service`:

```ini
[Unit]
Description=Emacs Daemon
After=graphical.target

[Service]
Type=simple
ExecStart=/usr/bin/emacs --daemon
Restart=on-failure

[Install]
WantedBy=default.target
```

Then manage with systemd:

```bash
# Reload systemd
systemctl --user daemon-reload

# Start daemon
systemctl --user start emacs

# Stop daemon
systemctl --user stop emacs

# Restart daemon
systemctl --user restart emacs

# Check status
systemctl --user status emacs
```

### Manual Start (Development)

```bash
# Background daemon (recommended for development)
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 emacs --bg-daemon=copilot-auto-workflow

# Foreground daemon (for debugging)
emacs --fg-daemon
```

## Managing the Daemon

### Essential Commands

| Task | Command |
|------|---------|
| Check if daemon running | `pgrep -f "Emacs.*daemon"` |
| Count daemon processes | `pgrep -f "Emacs.*daemon" | wc -l` |
| Test daemon responsive | `emacsclient -e "(+ 1 1)"` |
| View daemon logs | `tail -f /tmp/emacs-daemon.log` |
| Kill all Emacs processes | `pkill -9 -f Emacs` |

### Verify Daemon is Running

```bash
# Quick check - should return 1
pgrep -f "Emacs.*daemon" | wc -l

# Or use emacsclient
emacsclient -e "(user-emacs-directory)" && echo "✅ Daemon running"
```

### Connect to Daemon

```bash
# Open new frame (GUI)
emacsclient -c

# Open new frame in terminal
emacsclient -t

# Evaluate expression without opening frame
emacsclient -e "(message \"Hello\")"

# Open file
emacsclient /path/to/file
```

## Anti-Pattern: Stale Compiled Files

### Problem

Compiled `.elc` files persist across daemon restarts, causing stale code to run:

1. Make changes to `.el` file
2. Restart daemon
3. Changes not reflected
4. Old compiled code still running

### Root Cause

Emacs loads `.elc` if it exists, and restarting daemon doesn't recompile.

### Solution: Remove Stale .elc Files

```bash
# Remove all compiled files in lisp directory
rm -f lisp/modules/*.elc

# Kill all Emacs processes
killall -9 Emacs

# Remove temp files
rm -rf /tmp/emacs*

# Start fresh daemon
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 emacs --bg-daemon=copilot-auto-workflow
```

### Prevention Options

**Option 1: Never compile specific files**
```elisp
;; -*- no-byte-compile: t; -*- at the top of the file
```

**Option 2: Prefer newer files**
```elisp
;; In early-init.el
(setq load-prefer-newer t)  ; Prefer .el over .elc
```

**Option 3: Clean before restart**
```bash
# Always clean before daemon restart
find . -name "*.elc" -delete
```

### Test for Fresh Code

```bash
rm -f lisp/modules/*.elc
emacs --batch -l lisp/modules/module.el -f some-function
```

## Anti-Pattern: Server Name Conflicts

### Problem

Multiple cron jobs using the same Emacs daemon server name cause conflicts:

```
"Unable to start daemon: Emacs server named X already running"
"failed to start worker daemon: X"
```

### Root Cause

Different actions (researcher vs auto-workflow) using identical `SERVER_NAME`.

### Solution: Use Unique Server Names

```bash
# Researcher daemon
emacs --daemon=copilot-researcher

# Auto-workflow daemon
emacs --daemon=copilot-auto-workflow

# Connect to specific daemon
emacsclient -s copilot-researcher -e "(+ 1 1)"
```

### Log File Differentiation

```bash
# Separate logs per daemon
emacs --daemon=copilot-researcher 2>/tmp/emacs-researcher.log
emacs --daemon=copilot-auto-workflow 2>/tmp/emacs-auto-workflow.log
```

## Anti-Pattern: Multiple Daemons

### Problem

Running multiple Emacs daemons causes:
- Port/socket conflicts
- Client connection issues
- Resource waste
- Confusing behavior

### Solution: Single Daemon Check Script

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

# Start fresh daemon (platform-specific)
if [[ "$OSTYPE" == "darwin"* ]]; then
    launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
else
    systemctl --user restart emacs
fi

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

## Theme Management in Daemon Mode

### Problem

When running as daemon, GUI themes don't load automatically because:
- Daemon starts headless without display
- Theme settings apply to non-existent frames
- New frames via `emacsclient -c` don't inherit settings

### Solution: Reload Theme File on Frame Creation

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
- **Automatic consistency**: Changes to theme file automatically apply
- **Complete coverage**: Fonts, transparency, fullscreen, line numbers all work
- **Maintainable**: No duplicated code

### Verify Theme Applied

```bash
emacsclient -c -n
emacsclient -e "(face-attribute 'default :background)"
# Should return "#262626" or your theme color
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

```python
with open("lisp/modules/gptel-tools-agent.el", "r") as f:
    content = f.read()
print(f"Open: {content.count('(')}, Close: {content.count(')')}")
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

## Platform-Specific Notes

### macOS

- Use `launchctl` for production/auto-start
- Use manual commands for development/debugging
- GUI Emacs vs daemon: Choose one approach, not both
- `MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1` doesn't prevent server name conflicts

### Debian/Linux

- Always use `systemctl --user` for management
- Don't use direct `emacs --daemon` if systemd is managing it
- Socket file at `/run/user/1000/emacs/server` may already exist
- `emacsclient --eval "(kill-emacs)"` can hang; use systemctl instead

### Process Conflicts

| Scenario | Issue | Resolution |
|----------|-------|------------|
| GUI Emacs + daemon | Separate servers, client connects to first | Use daemon + emacsclient -c only |
| Multiple cron jobs | Server name conflicts | Unique names per action |
| Stale socket | "Cannot connect to server" | Remove /tmp/emacs* files |

## Key Principles

1. **Single daemon rule**: Always ensure only one daemon runs
2. **Unique server names**: Use action-specific names (e.g., `copilot-researcher` vs `copilot-auto-workflow`)
3. **Clean before restart**: Remove `.elc` files to avoid stale code
4. **Use proper tools**: launchctl (macOS) or systemctl (Linux), not direct commands
5. **Theme reload hook**: Use `after-make-frame-functions` for daemon theme management
6. **Verify after changes**: Always test with `emacsclient -e` after configuration changes

## Related

- [Emacs Configuration](emacs-configuration)
- [Emacs Client](emacs-client)
- [Launch Agents](launch-agents)
- [Systemd Services](systemd-services)
- [Process Management](process-management)