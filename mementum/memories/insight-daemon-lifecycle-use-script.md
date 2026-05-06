# Use the auto-workflow script for daemon lifecycle, not manual kill/start

**Target:** scripts/run-auto-workflow-cron.sh

The auto-workflow daemon must be managed through the script, not via manual `kill`/`Emacs` commands. The script handles critical setup that manual operations miss:

1. **Daemon guard bypass**: `post-early-init.el` blocks multiple daemons. The script sets `MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1` to allow the workflow daemon.
2. **Socket cleanup**: `clean_orphaned_sockets` removes stale socket files before starting.
3. **SSH keys**: `ensure_ssh_keys_loaded` adds keys to agent (needed for git push).
4. **Submodules**: `hydrate_missing_worktree_submodules` ensures worktree submodules exist.
5. **Native comp disabled**: `EMACSNATIVELOADPATH=` prevents stale `.eln` cache issues.
6. **Process isolation**: Uses `setsid` + `--fg-daemon` so the daemon survives the script process.

**Commands:**
- Start/run: `./scripts/run-auto-workflow-cron.sh auto-workflow`
- Stop: `./scripts/run-auto-workflow-cron.sh stop`
- Status: `./scripts/run-auto-workflow-cron.sh status`
- Messages: `./scripts/run-auto-workflow-cron.sh messages`

**Don't:** `kill <pid>`, `emacs --bg-daemon=copilot-auto-workflow` — these skip setup and create orphan sockets or duplicate daemons.
