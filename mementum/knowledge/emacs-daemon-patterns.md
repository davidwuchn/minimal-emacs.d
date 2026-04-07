---
title: Emacs Daemon Patterns for minimal-emacs.d
status: active
category: knowledge
tags: [emacs, daemon, cron, systemd, macos, launchd]
related: [mementum/memories/daemon-server-name-conflict.md, mementum/memories/daemon-persistence-antipattern.md]
---

# Emacs Daemon Patterns for minimal-emacs.d

Patterns for running Emacs as a daemon for auto-workflow, research, and autonomous operation.

## Server Name Isolation

**Problem:** Multiple cron jobs (auto-workflow, researcher, mementum) using the same Emacs server name cause "already running" errors.

**Solution:** Use action-specific server names:
- `copilot-auto-workflow` for auto-workflow cron job
- `copilot-researcher` for research cron job
- Separate log files per daemon: `${SERVER_NAME}.log`

**Implementation:**
```bash
case "$ACTION" in
    auto-workflow) SERVER_NAME="copilot-auto-workflow" ;;
    research) SERVER_NAME="copilot-researcher" ;;
    *) SERVER_NAME="copilot-auto-workflow" ;;
esac
```

**Commit:** `939928cf`

---

## Daemon Persistence Anti-Pattern

**Problem:** Relying on a single persistent daemon causes state accumulation and conflicts between different workflows.

**Solution:** Use on-demand daemon startup with proper cleanup:
- Start daemon when needed via `--bg-daemon=$SERVER_NAME`
- Check if daemon exists before starting new one
- Use separate daemons for different workflows

**Avoid:**
- Single long-running daemon for all cron jobs
- Never restarting daemon
- Shared state between unrelated workflows

---

## Platform-Specific Setup

### macOS (launchd)

- No `XDG_RUNTIME_DIR` needed
- PATH: `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`
- Schedule: 10AM, 2PM, 6PM (3 runs/day, interactive use hours)

### Linux/Pi5 (systemd)

- Set `XDG_RUNTIME_DIR=/run/user/$(id -u)`
- Use `systemctl --user start emacs` for persistent daemon
- Schedule: 11PM, 3AM, 7AM, 11AM, 3PM, 7PM (6 runs/day, 24/7 headless)

---

## Theme Reloading Strategy

**Problem:** Emacs daemon doesn't load themes correctly after daemon start.

**Solution:** Force theme reload in `server-after-make-frame-hook`:
```elisp
(add-hook 'server-after-make-frame-hook
          (lambda () (load-theme 'my-theme t)))
```

---

## Key Principles

1. **Isolation:** Separate server names per workflow
2. **On-demand:** Start daemons when needed, not always-on
3. **Cleanup:** Remove merged experiment worktrees
4. **Logs:** Separate log files per daemon for debugging
5. **Platform-aware:** Different paths and settings per OS

---

## Related Memories

- `daemon-server-name-conflict.md` - Multiple cron jobs conflict
- `daemon-persistence-antipattern.md` - Single daemon anti-pattern
- `emacs-daemon-macos.md` - macOS specific setup
- `emacs-daemon-systemctl.md` - Linux systemd setup
- `emacs-daemon-theme-reload.md` - Theme loading fix
- `emacs-daemon-lessons.md` - General lessons learned
- `systemctl-emacs-daemon.md` - systemd integration