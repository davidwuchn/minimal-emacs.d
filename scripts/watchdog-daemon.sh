#!/usr/bin/env bash
# Watchdog: restart auto-workflow daemon if unresponsive
# Runs from cron every 30min. Checks daemon socket via emacsclient.
# If daemon doesn't respond within 60s (600s when workflow active), kill and restart.
# Skips if daemon is CPU-busy (state R) — means it's executing code.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_NAME="ov5-auto-workflow"
SOCKET_PATH=""  # Resolved below from candidates
LOG="$DIR/var/tmp/cron/watchdog.log"
MAX_WAIT=60
RESTART_COOLDOWN=300  # 5 min between restarts to avoid restart loops

# Socket path resolution: try all candidate paths in priority order.
# Emacs creates the daemon socket at the first available of:
#   1. $XDG_RUNTIME_DIR/emacs/$name  (systemd Linux — /run/user/UID/emacs/$name)
#   2. $TMPDIR/emacs$UID/$name        (macOS default)
#   3. /tmp/emacs$UID/$name           (fallback for all platforms)
resolve_socket_path() {
    local name="$1"
    local uid="$2"
    # Check XDG_RUNTIME_DIR first (Debian/Ubuntu with systemd)
    if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/emacs/$name" ]; then
        echo "$XDG_RUNTIME_DIR/emacs/$name"
        return
    fi
    # Check TMPDIR (macOS)
    if [ -n "${TMPDIR:-}" ] && [ -S "$TMPDIR/emacs$uid/$name" ]; then
        echo "$TMPDIR/emacs$uid/$name"
        return
    fi
    # Fallback: /tmp/emacs$uid/$name
    if [ -S "/tmp/emacs$uid/$name" ]; then
        echo "/tmp/emacs$uid/$name"
        return
    fi
    echo "/tmp/emacs$uid/$name"  # Last resort: assume this path
}

SOCKET_PATH=$(resolve_socket_path "$SERVER_NAME" "$(id -u)")

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
    # Skip pipe-I/O kill when a workflow is active.  The daemon
    # legitimately waits on pipe I/O during LLM API calls (curl via
    # url-retrieve) and during blocking subprocesses (byte-compile,
    # git).  Killing mid-workflow loses progress and orphaned state.
    # Let the socket-response test below handle truly stuck daemons.
    if ! timeout 10 emacsclient -s "$SERVER_NAME" --eval \
         '(and (boundp (quote gptel-auto-workflow--running))
               gptel-auto-workflow--running)' >/dev/null 2>&1; then
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
fi

# Check if daemon responds.  When a workflow is running, use a generous
# timeout (600s) to avoid killing the daemon mid-experiment during an API call.
WORKFLOW_ACTIVE=0
if timeout 5 emacsclient -a false -s "$SERVER_NAME" --eval \
    '(and (boundp (quote gptel-auto-workflow--running)) gptel-auto-workflow--running)' >/dev/null 2>&1; then
    WORKFLOW_ACTIVE=1
fi

if [ "$WORKFLOW_ACTIVE" -eq 1 ]; then
    WORKFLOW_TIMEOUT=600  # 10 min grace period when busy
    echo "[$(date '+%H:%M:%S')] Workflow active — using ${WORKFLOW_TIMEOUT}s timeout" >> "$LOG"
else
    WORKFLOW_TIMEOUT="$MAX_WAIT"
fi

if ! timeout "$WORKFLOW_TIMEOUT" emacsclient -a false -s "$SERVER_NAME" --eval 't' >/dev/null 2>&1; then
    echo "[$(date '+%H:%M:%S')] Daemon unresponsive (${WORKFLOW_TIMEOUT}s timeout, workflow_active=$WORKFLOW_ACTIVE), killing" >> "$LOG"
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
