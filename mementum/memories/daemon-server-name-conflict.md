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