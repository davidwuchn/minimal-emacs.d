---
layout: memory
category: pattern
tags: [daemon, socket, watchdog, ov5-auto-workflow]
related: [mementum/memories/daemon-socket-cleanup.md]
---

# Daemon Stability: Socket Staleness and Watchdog Interactions

## Problem

The ov5-auto-workflow daemon enters a restart loop where:
1. Daemon starts successfully
2. Experiments begin running
3. Daemon becomes unresponsive (stuck on API calls or native compilation)
4. Watchdog detects unresponsiveness and kills daemon
5. Socket file remains stale
6. New daemon starts but emacsclient connects to old socket
7. Cycle repeats

## Root Causes

### 1. XDG_RUNTIME_DIR Permission Denied
- Cron jobs inherit XDG_RUNTIME_DIR=/run/user/$(id -u) from systemd user session
- When cron runs outside user session, /run/user/$(id -u) may be inaccessible
- Emacs daemon fails to create socket there, falls back to /tmp/emacs$UID/
- emacsclient still checks XDG_RUNTIME_DIR first, finds stale socket or no socket

**Fix:** Removed XDG_RUNTIME_DIR from crontab. Watchdog now unsets XDG_RUNTIME_DIR when starting daemon.

### 2. gptel-auto-workflow--load-skill Returns Nil
- Function had `when` block after `list` returning plist
- `when` evaluates to nil when condition is false
- Entire function returned nil instead of skill plist
- Category-specific prompt templates never loaded, fell back to hardcoded template
- Fallback template was weaker (no edit mandate)

**Fix:** Wrapped skill plist in `prog1` so `when` side-effect doesn't swallow return value.

### 3. Watchdog Cooldown Prevents Recovery
- RESTART_COOLDOWN=300s means after restart, watchdog won't restart again for 5 minutes
- If daemon dies immediately, system waits 5 minutes before trying again
- During this window, no experiments run

**Fix:** Reduced cooldown consideration - manually bypass when needed.

### 4. Emacs Native Compilation Blocks Daemon
- On startup, Emacs compiles .el files to native code
- This can take 30-60 seconds and block the server
- During compilation, emacsclient times out
- Watchdog interprets timeout as daemon death

**Mitigation:** Set `native-comp-jit-compilation nil` in daemon startup.

## Diagnostic Commands

```bash
# Check daemon process
ps aux | grep "ov5-auto-workflow" | grep -v grep

# Check socket responsiveness
python3 -c "import socket; s=socket.socket(socket.AF_UNIX); s.settimeout(2); s.connect('/tmp/emacs1000/ov5-auto-workflow'); s.send(b'(+ 1 1)\\n'); print(s.recv(1024)); s.close()"

# Check socket ownership
lsof /tmp/emacs1000/ov5-auto-workflow

# Check watchdog log
tail -20 /home/davidwu/.emacs.d/var/tmp/cron/watchdog.log

# Force daemon restart
rm -f /home/davidwu/.emacs.d/var/tmp/cron/watchdog-last-restart
./scripts/watchdog-daemon.sh
```

## Resolution Order

1. **Kill stale processes:** `pkill -9 -f "ov5-auto-workflow"`
2. **Remove stale socket:** `rm -f /tmp/emacs1000/ov5-auto-workflow`
3. **Clear watchdog cooldown:** `rm -f /home/davidwu/.emacs.d/var/tmp/cron/watchdog-last-restart`
4. **Restart daemon:** `./scripts/watchdog-daemon.sh`
5. **Verify:** `env -u XDG_RUNTIME_DIR emacsclient -s /tmp/emacs1000/ov5-auto-workflow --eval "(+ 1 1)"`

## Prevention

- Always unset XDG_RUNTIME_DIR for cron-started daemons
- Ensure `prog1` or explicit returns in functions with side-effects
- Consider increasing watchdog grace period for active workflows
- Monitor daemon memory (RSS) - OOM kills also cause restart loops
