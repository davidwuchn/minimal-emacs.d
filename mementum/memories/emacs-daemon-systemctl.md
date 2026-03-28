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