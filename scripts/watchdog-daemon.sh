#!/usr/bin/env bash
# Watchdog: restart auto-workflow daemon if unresponsive
# Runs from cron every 30min. Checks daemon socket via emacsclient.
# If daemon doesn't respond within 60s (600s when workflow active), kill and restart.
# Skips if daemon is CPU-busy (state R) — means it's executing code.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_NAME="pmf-value-stream"
MY_UID=$(id -u)
LOG="$DIR/var/tmp/cron/watchdog.log"
LOCK_FILE="$DIR/var/tmp/cron/watchdog.lock"
MAX_WAIT=60
RESTART_COOLDOWN=300  # 5 min between restarts to avoid restart loops

# Cron runs without TMPDIR set; emacsclient needs it for socket discovery on macOS.
export TMPDIR=${TMPDIR:-/tmp}

mkdir -p "$(dirname "$LOG")"

start_workflow_daemon() {
    env -u DISPLAY -u WAYLAND_DISPLAY -u WAYLAND_SOCKET -u XAUTHORITY -u XDG_RUNTIME_DIR \
        EMACSNATIVELOADPATH= \
        TMPDIR=/tmp \
        AUTO_WORKFLOW_EMACS_SERVER="$SERVER_NAME" \
        MINIMAL_EMACS_WORKFLOW_ROLE=auto-workflow \
        MINIMAL_EMACS_WORKFLOW_DAEMON=1 \
        MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 \
        bash -c 'ulimit -s 65532 2>/dev/null; exec emacs --init-directory="$0" --daemon="$1" --eval "(setq native-comp-jit-compilation nil)" </dev/null' \
        "$DIR" "$SERVER_NAME" &
}

daemon_pids() {
    local name="$1"
    local pids=""

    if command -v pgrep >/dev/null 2>&1; then
        pids=$(pgrep -f -i "emacs.*daemon.*${name}" 2>/dev/null || true)
        if [ -n "$pids" ]; then
            echo "$pids"
            return 0
        fi
        # pgrep found nothing — try ps as fallback for macOS bg-daemon
    fi
    ps -axo pid=,command= | awk -v name="$name" '
        index(tolower($0), "emacs") && index(tolower($0), tolower(name)) { print $1 }
    '
}

first_daemon_pid() {
    daemon_pids "$1" | awk 'NF { print; exit }'
}

# Prevent concurrent watchdog runs. If the previous instance is still
# running after 120s, force-clear the lock (stale lock from crash).
if [ -f "$LOCK_FILE" ]; then
    lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        lock_age=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || stat -f %m "$LOCK_FILE" 2>/dev/null || date +%s)))
        if [ "$lock_age" -lt 120 ]; then
            exit 0  # Another watchdog is already running
        fi
        # Stale lock — clean up
        rm -f "$LOCK_FILE"
    else
        rm -f "$LOCK_FILE"
    fi
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# Clean all candidate socket paths for this server/UID.
# Stale sockets from crashed daemons block emacsclient from connecting
# because Emacs skips socket directories that already exist.
# On macOS, lsof -t doesn't work for Unix domain sockets, so we clean
# sockets only when we know the daemon is dead (after killing).
clean_all_sockets() {
    local name="$1" uid="$2"
    # Clean ALL candidate socket paths, including hardcoded /run/user
    # (daemons started outside cron may use XDG_RUNTIME_DIR even when
    # cron unsets it).
    for base in "${XDG_RUNTIME_DIR:-}" "${TMPDIR:-}" /tmp "/run/user/$uid"; do
        [ -n "$base" ] || continue
        # XDG_RUNTIME_DIR uses "emacs/NAME" instead of "emacs$uid/NAME"
        local socket
        if [ "$base" = "${XDG_RUNTIME_DIR:-}" ] || [ "$base" = "/run/user/$uid" ]; then
            socket="$base/emacs/$name"
        else
            socket="$base/emacs$uid/$name"
        fi
        if [ -e "$socket" ] || [ -L "$socket" ]; then
            rm -f "$socket" 2>/dev/null || true
            echo "[$(date '+%H:%M:%S')] Cleaned socket: $socket" >> "$LOG"
        fi
    done
}

# Resolve the live socket path for a given server name and UID.
# Checks candidate directories, verifies a process is actually listening.
# Returns 0 with SOCKET_PATH set on success, 1 on failure.
resolve_live_socket() {
    local name="$1" uid="$2" sock=""
    for base in "${XDG_RUNTIME_DIR:-}" "${TMPDIR:-}" /tmp "/run/user/$uid"; do
        [ -n "$base" ] || continue
        if [ "$base" = "${XDG_RUNTIME_DIR:-}" ] || [ "$base" = "/run/user/$uid" ]; then
            sock="$base/emacs/$name"
        else
            sock="$base/emacs$uid/$name"
        fi
        if [ -S "$sock" ]; then
            SOCKET_PATH="$sock"
            return 0
        fi
    done
    return 1
}

socket_accepts_connections() {
    python3 - "$SERVER_NAME" "$MY_UID" <<'PY'
from pathlib import Path
import os
import socket
import sys
import tempfile

server_name = sys.argv[1]
uid = sys.argv[2]

def candidate_socket_paths(name, uid_value):
    candidates = []
    for base in filter(None, [os.environ.get("XDG_RUNTIME_DIR"),
                              os.environ.get("TMPDIR"),
                              tempfile.gettempdir(),
                              "/tmp",
                              f"/run/user/{uid_value}"]):
        if base == os.environ.get("XDG_RUNTIME_DIR") or base == f"/run/user/{uid_value}":
            candidates.append(Path(base) / "emacs" / name)
        else:
            candidates.append(Path(base) / f"emacs{uid_value}" / name)
    deduped = []
    seen = set()
    for path in candidates:
        key = str(path)
        if key not in seen:
            deduped.append(path)
            seen.add(key)
    return deduped

for socket_path in candidate_socket_paths(server_name, uid):
    if not socket_path.exists():
        continue
    probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    probe.settimeout(1)
    try:
        probe.connect(str(socket_path))
        raise SystemExit(0)
    except ConnectionRefusedError:
        raise SystemExit(1)
    except socket.timeout:
        # Timeout means socket exists but server not responding — treat as broken
        raise SystemExit(1)
    except OSError:
        continue
    finally:
        probe.close()

raise SystemExit(1)
PY
}

# Check if daemon is reachable via emacsclient.
# First verify the process exists — a busy Emacs blocked on API calls
# still has its process running, just can't respond to emacsclient.
# Returns 0 if responsive or process is alive (busy), 1 if truly gone.
daemon_responds() {
    timeout 5 emacsclient -a false -s "$SERVER_NAME" --eval 't' >/dev/null 2>&1 && return 0
    # A refused Unix socket means the server endpoint is broken, not just busy.
    if ! socket_accepts_connections; then
        return 1
    fi
    # Daemon didn't respond via emacsclient — it might be busy with an API call.
    # Check if the process itself is still alive (R=Running, S=Sleeping, D=uninterruptible I/O).
    local pid
    pid=$(first_daemon_pid "$SERVER_NAME")
    if [ -n "$pid" ]; then
        local state
        state=$(ps -p "$pid" -o state= 2>/dev/null | tr -d ' ')
        if [ -n "$state" ] && echo "$state" | grep -qE '^[RSUD]'; then
            return 0  # Process is alive, just busy
        fi
        echo "[$(date '+%H:%M:%S')] Daemon pid=$pid state=$state (not alive)" >> "$LOG"
    else
        echo "[$(date '+%H:%M:%S')] Daemon PID not found" >> "$LOG"
    fi
    return 1
}

# Check if a workflow is currently active by reading the status file.
# Using the status file instead of emacsclient is critical: when the
# daemon is busy with an API call (gptel-request), emacsclient blocks
# and times out, making a healthy daemon look unresponsive.  The status
# file is written to disk before any long-running operation.
workflow_active() {
    local status_file="$DIR/var/tmp/cron/auto-workflow-status.sexp"
    if [ -f "$status_file" ]; then
        grep -q ':running t' "$status_file" 2>/dev/null && return 0
    fi
    return 1
}

# Check if a process is actively running (not stuck) without /proc.
# macOS-compatible: uses ps to get process state.
proc_is_running() {
    local pid="$1"
    [ -z "$pid" ] && return 1
    # Include D (uninterruptible sleep) — common during API I/O waits
    ps -p "$pid" -o state= 2>/dev/null | grep -qE '^[RSUD]'
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

# Try to reach the daemon via emacsclient. This is the canonical check —
# it matches what users and other scripts use, and handles socket resolution
# (TMPDIR vs /tmp) automatically.
if daemon_responds; then
    # Daemon is alive and responsive. Check memory usage — if the
    # daemon process RSS exceeds 1GB, restart it gracefully to prevent
    # OOM. Long-running Emacs accumulates memory from experiment data
    # and cached results that GC can't fully reclaim.
    # Get daemon PID via emacsclient (pgrep fails due to --bg-daemon escape chars)
    DAEMON_RSS_PID=$(timeout 5 emacsclient -s "$SERVER_NAME" --eval '(emacs-pid)' 2>/dev/null | tr -d '"' | tr -d '\n')
    if [ -n "$DAEMON_RSS_PID" ] && [ "$DAEMON_RSS_PID" -gt 0 ] 2>/dev/null; then
        RSS_KB=$(ps -p "$DAEMON_RSS_PID" -o rss= 2>/dev/null | tr -d ' ')
        if [ -n "$RSS_KB" ] && [ "$RSS_KB" -gt 5242880 ]; then  # > 5GB
            echo "[$(date '+%H:%M:%S')] High memory (${RSS_KB}KB) — graceful restart" >> "$LOG"
            timeout 30 emacsclient -s "$SERVER_NAME" --eval '(kill-emacs)' >/dev/null 2>&1 || true
            sleep 5
            clean_all_sockets "$SERVER_NAME" "$MY_UID"
            echo "$(date +%s)" > "$LAST_RESTART_FILE"
            start_workflow_daemon
            exit 0
        fi
    fi
    # Also check researcher daemon memory (persists between pipeline runs)
    RESEARCHER_PID=$(first_daemon_pid "gtm-product-org")
    if [ -n "$RESEARCHER_PID" ]; then
        RSS_KB=$(ps -p "$RESEARCHER_PID" -o rss= 2>/dev/null | tr -d ' ')
        if [ -n "$RSS_KB" ] && [ "$RSS_KB" -gt 5242880 ]; then
            echo "[$(date '+%H:%M:%S')] High researcher memory (${RSS_KB}KB) — killing" >> "$LOG"
            kill -9 "$RESEARCHER_PID" 2>/dev/null || true
            echo "$(date +%s)" > "$LAST_RESTART_FILE"
        fi
    fi
    exit 0
fi

# Daemon not responding. Check if a workflow is active — if so,
# give it a generous grace period (API calls can take minutes).
if workflow_active; then
    echo "[$(date '+%H:%M:%S')] Workflow active — using 1200s grace period" >> "$LOG"
    # The daemon may be initializing (process alive but no socket yet).
    # Poll for the socket and responsiveness instead of returning immediately.
    _deadline=$(($(date +%s) + 1200))
    while [ $(date +%s) -lt $_deadline ]; do
        if daemon_responds; then
            echo "[$(date '+%H:%M:%S')] Daemon responsive after workflow wait" >> "$LOG"
            exit 0  # Daemon came back
        fi
        # If the daemon process exists, keep waiting for the socket.
        _pid=$(first_daemon_pid "$SERVER_NAME")
        if [ -z "$_pid" ]; then
            echo "[$(date '+%H:%M:%S')] Workflow grace: PID not found, breaking" >> "$LOG"
            break  # Process is gone — not coming back
        fi
        if ! kill -0 "$_pid" 2>/dev/null; then
            echo "[$(date '+%H:%M:%S')] Workflow grace: PID $_pid dead, breaking" >> "$LOG"
            break
        fi
        sleep 5
    done
    if [ $(date +%s) -ge $_deadline ]; then
        echo "[$(date '+%H:%M:%S')] Workflow grace period expired" >> "$LOG"
    fi
fi

# Daemon is truly gone. Kill all processes, clean sockets, restart.
echo "[$(date '+%H:%M:%S')] Daemon unresponsive — restarting" >> "$LOG"
daemon_pids "$SERVER_NAME" | xargs kill -9 2>/dev/null || true
sleep 3
clean_all_sockets "$SERVER_NAME" "$MY_UID"
echo "$(date +%s)" > "$LAST_RESTART_FILE"
start_workflow_daemon
echo "[$(date '+%H:%M:%S')] Daemon restarted" >> "$LOG"
exit 0
