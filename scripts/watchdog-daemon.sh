#!/usr/bin/env bash
# Watchdog: restart auto-workflow daemon if unresponsive
# Runs from cron every 30min. Checks daemon socket via emacsclient.
# If daemon doesn't respond within 60s (600s when workflow active), kill and restart.
# Skips if daemon is CPU-busy (state R) — means it's executing code.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_NAME="ov5-auto-workflow"
MY_UID=$(id -u)
LOG="$DIR/var/tmp/cron/watchdog.log"
MAX_WAIT=60
RESTART_COOLDOWN=300  # 5 min between restarts to avoid restart loops

# Clean all candidate socket paths for this server/UID.
# Stale sockets from crashed daemons block emacsclient from connecting
# because Emacs skips socket directories that already exist.
clean_all_sockets() {
    local name="$1" uid="$2"
    for base in "${XDG_RUNTIME_DIR:-}" "${TMPDIR:-}" /tmp; do
        [ -n "$base" ] || continue
        local socket="$base/emacs$uid/$name"
        if [ -e "$socket" ] || [ -L "$socket" ]; then
            if ! lsof -t "$socket" >/dev/null 2>&1; then
                rm -f "$socket" 2>/dev/null || true
                echo "[$(date '+%H:%M:%S')] Cleaned stale socket: $socket" >> "$LOG"
            fi
        fi
    done
}

# Resolve the live socket path (same logic as emacsclient internal resolution).
# Returns the first socket that exists AND has a listener.
resolve_live_socket() {
    local name="$1" uid="$2"
    for base in "${XDG_RUNTIME_DIR:-}" "${TMPDIR:-}" /tmp; do
        [ -n "$base" ] || continue
        local socket="$base/emacs$uid/$name"
        if [ -S "$socket" ] && lsof -t "$socket" >/dev/null 2>&1; then
            echo "$socket"
            return 0
        fi
    done
    return 1
}

mkdir -p "$(dirname "$LOG")"

# Avoid restart loops: track last restart time
LAST_RESTART_FILE="$DIR/var/tmp/cron/watchdog-last-restart"
if [ -f "$LAST_RESTART_FILE" ]; then
    last_restart=$(cat "$LAST_RESTART_FILE")
    now=$(date +%s)
    if [ $((now - last_restart)) -lt $RESTART_COOLDOWN ]; then
        exit 0
    fi
fi

# Try to reach the daemon via emacsclient first (uses its own socket resolution)
if timeout 5 emacsclient -a false -s "$SERVER_NAME" --eval 't' >/dev/null 2>&1; then
    # Daemon is responsive. Check if workflow is active for logging only.
    if timeout 5 emacsclient -s "$SERVER_NAME" --eval \
        '(and (boundp (quote gptel-auto-workflow--running)) gptel-auto-workflow--running)' >/dev/null 2>&1; then
        # Workflow active — daemon is busy, everything is fine
        exit 0
    fi
    # Idle daemon, responsive — all good
    exit 0
fi

# Daemon not responding to emacsclient. Find out why.

# Resolve the live socket (with listener check, not just file existence)
SOCKET_PATH=""
if SOCKET_PATH=$(resolve_live_socket "$SERVER_NAME" "$MY_UID"); then
    :  # Live socket found — daemon has a socket but not responding
else
    # No live socket. Check if there's a socket file without listener (stale).
    # Clean ALL candidate paths so the next daemon starts clean.
    echo "[$(date '+%H:%M:%S')] No live socket — cleaning stale sockets and restarting" >> "$LOG"
    clean_all_sockets "$SERVER_NAME" "$MY_UID"
    echo "$(date +%s)" > "$LAST_RESTART_FILE"
    MINIMAL_EMACS_WORKFLOW_DAEMON=1 MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 \
        bash -c 'ulimit -s 65532 2>/dev/null; exec emacs --init-directory="$0" --daemon="$1" </dev/null' \
        "$DIR" "$SERVER_NAME" &
        echo "[$(date '+%H:%M:%S')] Daemon restarted after socket cleanup" >> "$LOG"
    exit 0
fi

# Check if daemon process exists
DAEMON_PID=$(pgrep -f "emacs.*--daemon=${SERVER_NAME}" 2>/dev/null || true)
if [ -n "$DAEMON_PID" ]; then
    # Check if daemon is actively running (not stuck on I/O)
    PROC_STATE=$(cat /proc/$DAEMON_PID/status 2>/dev/null | grep "^State:" | awk '{print $2}' || echo "?")
    if [ "$PROC_STATE" = "R" ]; then
        # Actively executing — don't kill, it's busy
        exit 0
    fi
    # Check if workflow is active - if so, use generous timeout
    WORKFLOW_ACTIVE=0
    if timeout 5 emacsclient -s "$SERVER_NAME" --eval \
        '(and (boundp (quote gptel-auto-workflow--running)) gptel-auto-workflow--running)' >/dev/null 2>&1; then
        WORKFLOW_ACTIVE=1
    fi
    if [ "$WORKFLOW_ACTIVE" -eq 1 ]; then
        echo "[$(date '+%H:%M:%S')] Workflow active — using 600s timeout" >> "$LOG"
        if timeout 600 emacsclient -a false -s "$SERVER_NAME" --eval 't' >/dev/null 2>&1; then
            exit 0  # Responded within grace period
        fi
    fi
fi

# Daemon is truly unresponsive. Kill ALL instances, clean sockets, restart.
echo "[$(date '+%H:%M:%S')] Daemon unresponsive — killing all instances and restarting" >> "$LOG"
# Kill all daemon processes matching this server name.
# The --bg-daemon flag uses escaped args, so match broadly.
pgrep -f "emacs.*daemon.*${SERVER_NAME}" | xargs kill -9 2>/dev/null || true
pgrep -f "emacs.*--bg-daemon.*${SERVER_NAME}" | xargs kill -9 2>/dev/null || true
pgrep -f "emacs.*--daemon=${SERVER_NAME}" | xargs kill -9 2>/dev/null || true
sleep 3
clean_all_sockets "$SERVER_NAME" "$MY_UID"
echo "$(date +%s)" > "$LAST_RESTART_FILE"
MINIMAL_EMACS_WORKFLOW_DAEMON=1 MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 \
    bash -c 'ulimit -s 65532 2>/dev/null; exec emacs --init-directory="$0" --daemon="$1" </dev/null' \
    "$DIR" "$SERVER_NAME" &
echo "[$(date '+%H:%M:%S')] Daemon restarted" >> "$LOG"
exit 0
