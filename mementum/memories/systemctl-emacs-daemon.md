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