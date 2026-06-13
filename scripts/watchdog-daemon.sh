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

start_gtm_daemon() {
    env -u DISPLAY -u WAYLAND_DISPLAY -u WAYLAND_SOCKET -u XAUTHORITY -u XDG_RUNTIME_DIR \
        EMACSNATIVELOADPATH= \
        TMPDIR=/tmp \
        AUTO_WORKFLOW_EMACS_SERVER=gtm-product-org \
        MINIMAL_EMACS_WORKFLOW_ROLE=research \
        MINIMAL_EMACS_WORKFLOW_DAEMON=1 \
        MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 \
        bash -c 'ulimit -s 65532 2>/dev/null; exec emacs --init-directory="$0" --daemon="$1" --eval "(setq native-comp-jit-compilation nil)" </dev/null' \
        "$DIR" gtm-product-org &
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
    local socket_path
    local runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$MY_UID}"
    local tmpdir="${TMPDIR:-/tmp}"
    local candidates=(
        "$runtime_dir/emacs/$SERVER_NAME"
        "$tmpdir/emacs$MY_UID/$SERVER_NAME"
        "/tmp/emacs$MY_UID/$SERVER_NAME"
        "/run/user/$MY_UID/emacs/$SERVER_NAME"
    )
    local seen=""
    for socket_path in "${candidates[@]}"; do
        case "$seen" in
            *"|$socket_path|"*) continue ;;
        esac
        seen="${seen}|$socket_path|"
        [ -S "$socket_path" ] || continue
        # If lsof is available, verify a process owns the socket
        if command -v lsof >/dev/null 2>&1; then
            lsof "$socket_path" >/dev/null 2>&1 && return 0
            return 1
        fi
        # Without lsof, assume socket is good if file exists
        return 0
    done
    return 1
}

# Check if daemon is reachable via emacsclient.
# Uses heartbeat file for freeze detection: if the Emacs main thread is
# blocked (e.g. on an API call), timers stop firing and the heartbeat goes
# stale.  A daemon with fresh heartbeat is "alive" even if emacsclient hangs.
# Returns 0 if responsive or alive (fresh heartbeat), 1 if frozen/gone.
daemon_responds() {
    timeout 5 emacsclient -a false -s "$SERVER_NAME" --eval 't' >/dev/null 2>&1 && return 0
    # A refused Unix socket means the server endpoint is broken, not just busy.
    if ! socket_accepts_connections; then
        return 1
    fi
    # Daemon didn't respond via emacsclient — could be busy or frozen.
    # Check heartbeat: fresh => alive (legitimate blocking op), stale => frozen.
    if check_heartbeat_staleness; then
        return 0  # Heartbeat fresh — daemon is alive, just busy
    fi
    echo "[$(date '+%H:%M:%S')] Heartbeat stale AND emacsclient failed — daemon frozen" >> "$LOG"
    return 1
}

# Check if a workflow is currently active by reading the status file.
# Using the status file instead of emacsclient is critical: when the
# daemon is busy with an API call (gptel-request), emacsclient blocks
# and times out, making a healthy daemon look unresponsive.  The status
# file is written to disk before any long-running operation.
workflow_active() {
    local status_file="$DIR/var/tmp/cron/auto-workflow-status.edn"
    if [ -f "$status_file" ]; then
        grep -q ':running true' "$status_file" 2>/dev/null && return 0
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

# Check heartbeat file staleness.
# Returns 0 if heartbeat is fresh (< 90s old), 1 if stale or missing.
# This detects a frozen daemon: if the Emacs main thread is blocked on an
# API call, timers stop firing, and the heartbeat file goes stale.
# Threshold reduced from 180s to 90s for faster freeze detection (~90min issue).
check_heartbeat_staleness() {
    local hb_file="${1:-$DIR/var/tmp/daemon-heartbeat}"
    local threshold="${2:-90}"
    if [ ! -f "$hb_file" ]; then
        return 1
    fi
    local hb_ts
    hb_ts=$(head -1 "$hb_file" 2>/dev/null | tr -d '[:space:]')
    if [ -z "$hb_ts" ]; then
        return 1
    fi
    local now delta
    now=$(date +%s)
    delta=$((now - hb_ts))
    if [ "$delta" -lt "$threshold" ]; then
        return 0  # Fresh heartbeat — daemon is alive
    fi
    echo "[$(date '+%H:%M:%S')] Heartbeat stale: ${delta}s > ${threshold}s threshold" >> "$LOG"
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
        if [ -n "$RSS_KB" ] && [ "$RSS_KB" -gt 2621440 ]; then  # > 2.5GB
            echo "[$(date '+%H:%M:%S')] High memory (${RSS_KB}KB) — graceful restart" >> "$LOG"
            timeout 30 emacsclient -s "$SERVER_NAME" --eval '(kill-emacs)' >/dev/null 2>&1 || true
            sleep 5
            clean_all_sockets "$SERVER_NAME" "$MY_UID"
            echo "$(date +%s)" > "$LAST_RESTART_FILE"
            start_workflow_daemon
            exit 0
        fi
    fi
    # Also check GTM daemon (gtm-product-org) — restart if missing or memory high
    GTM_PID=$(first_daemon_pid "gtm-product-org")
    if [ -n "$GTM_PID" ]; then
        RSS_KB=$(ps -p "$GTM_PID" -o rss= 2>/dev/null | tr -d ' ')
        if [ -n "$RSS_KB" ] && [ "$RSS_KB" -gt 2621440 ]; then
            echo "[$(date '+%H:%M:%S')] High GTM memory (${RSS_KB}KB) — killing" >> "$LOG"
            kill -9 "$GTM_PID" 2>/dev/null || true
            sleep 3
            clean_all_sockets "gtm-product-org" "$MY_UID"
            echo "$(date +%s)" > "$LAST_RESTART_FILE"
            start_gtm_daemon
            echo "[$(date '+%H:%M:%S')] GTM daemon restarted (memory kill)" >> "$LOG"
        fi
    else
        # GTM daemon missing — start it
        echo "[$(date '+%H:%M:%S')] GTM daemon missing — starting" >> "$LOG"
        clean_all_sockets "gtm-product-org" "$MY_UID"
        echo "$(date +%s)" > "$LAST_RESTART_FILE"
        start_gtm_daemon
        echo "[$(date '+%H:%M:%S')] GTM daemon started" >> "$LOG"
    fi
    exit 0
fi

# Daemon not responding. Check if a workflow is active — if so,
# give it a grace period, BUT only if heartbeat is fresh (daemon alive but busy).
# If heartbeat is stale, the daemon is frozen — restart immediately.
if workflow_active; then
    if ! check_heartbeat_staleness; then
        echo "[$(date '+%H:%M:%S')] Workflow active BUT heartbeat stale — daemon frozen, skipping grace" >> "$LOG"
    else
        echo "[$(date '+%H:%M:%S')] Workflow active — using 300s grace (heartbeat fresh)" >> "$LOG"
        # The daemon may be initializing (process alive but no socket yet).
        # Poll for the socket and responsiveness instead of returning immediately.
        _deadline=$(($(date +%s) + 300))
        while [ $(date +%s) -lt $_deadline ]; do
            if daemon_responds; then
                echo "[$(date '+%H:%M:%S')] Daemon responsive after workflow wait" >> "$LOG"
                exit 0  # Daemon came back
            fi
            # If heartbeat goes stale during grace, break immediately
            if ! check_heartbeat_staleness; then
                echo "[$(date '+%H:%M:%S')] Workflow grace: heartbeat went stale, breaking" >> "$LOG"
                break
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
