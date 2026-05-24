#!/usr/bin/env bash
# Watchdog: restart auto-workflow daemon if unresponsive
# Runs from cron every 2 hours. Checks daemon socket via emacsclient.
# If daemon doesn't respond within 60s, kill and restart.
# Skips if daemon is CPU-busy (state R) — means it's executing code.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_NAME="ov5-auto-workflow"
SOCKET_PATH="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/emacs/$SERVER_NAME"
LOG="$DIR/var/tmp/cron/watchdog.log"
MAX_WAIT=60
RESTART_COOLDOWN=300  # 5 min between restarts to avoid restart loops

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

# Check if socket exists
if [ ! -S "$SOCKET_PATH" ]; then
    echo "[$(date '+%H:%M:%S')] Socket missing, restarting daemon" >> "$LOG"
    echo "$(date +%s)" > "$LAST_RESTART_FILE"
    MINIMAL_EMACS_WORKFLOW_DAEMON=1 MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 \
        bash -c 'ulimit -s 65532 2>/dev/null; exec emacs --init-directory="$0" --daemon="$1" </dev/null' \
        "$DIR" "$SERVER_NAME" &
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
    # Check for known stuck-on-pipe states (anon_pipe_read, pipe_wait, etc.)
    PROC_WCHAN=$(cat /proc/$DAEMON_PID/wchan 2>/dev/null || echo "")
    if echo "$PROC_WCHAN" | grep -q "anon_pipe_read\|pipe_wait\|pipe_read"; then
        echo "[$(date '+%H:%M:%S')] Daemon stuck on pipe I/O (wchan=$PROC_WCHAN), restarting" >> "$LOG"
        kill -9 "$DAEMON_PID" 2>/dev/null || true
        sleep 2
        rm -f "$SOCKET_PATH" 2>/dev/null || true
        echo "$(date +%s)" > "$LAST_RESTART_FILE"
        MINIMAL_EMACS_WORKFLOW_DAEMON=1 MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 \
            bash -c 'ulimit -s 65532 2>/dev/null; exec emacs --init-directory="$0" --daemon="$1" </dev/null' \
            "$DIR" "$SERVER_NAME" &
        echo "[$(date '+%H:%M:%S')] Daemon restarted after pipe stuck" >> "$LOG"
        exit 0
    fi
fi

# Check if daemon responds
if ! timeout "$MAX_WAIT" emacsclient -a false -s "$SERVER_NAME" --eval 't' >/dev/null 2>&1; then
    echo "[$(date '+%H:%M:%S')] Daemon unresponsive (${MAX_WAIT}s timeout), killing" >> "$LOG"
    # Kill all processes with this server name
    pgrep -f "emacs.*--\(daemon\|fg-daemon\)=${SERVER_NAME}" | xargs kill -9 2>/dev/null || true
    sleep 2
    # Clean stale socket
    rm -f "$SOCKET_PATH" 2>/dev/null || true
    # Restart
    echo "$(date +%s)" > "$LAST_RESTART_FILE"
    MINIMAL_EMACS_WORKFLOW_DAEMON=1 MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 \
        bash -c 'ulimit -s 65532 2>/dev/null; exec emacs --init-directory="$0" --daemon="$1" </dev/null' \
        "$DIR" "$SERVER_NAME" &
    echo "[$(date '+%H:%M:%S')] Daemon restarted" >> "$LOG"
fi
