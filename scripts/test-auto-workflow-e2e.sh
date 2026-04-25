#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$DIR/scripts/run-auto-workflow-cron.sh"
cd "$DIR"

SOCKET_PIDS=()
DAEMON_SERVERS=()
DAEMON_RUNTIME_DIRS=()
TEMP_ARTIFACTS=()
GLOBAL_SNAPSHOT_CACHE="$DIR/var/tmp/cron/copilot-auto-workflow-snapshot-paths.txt"
GLOBAL_SNAPSHOT_CACHE_BACKUP=""
GLOBAL_SNAPSHOT_CACHE_HAD_FILE=0

backup_global_snapshot_cache() {
    [ -n "$GLOBAL_SNAPSHOT_CACHE_BACKUP" ] && return 0

    GLOBAL_SNAPSHOT_CACHE_BACKUP="$(mktemp "$DIR/var/tmp/cron/test-snapshot-cache-XXXXXX")"
    TEMP_ARTIFACTS+=("$GLOBAL_SNAPSHOT_CACHE_BACKUP")

    if [ -e "$GLOBAL_SNAPSHOT_CACHE" ]; then
        cp "$GLOBAL_SNAPSHOT_CACHE" "$GLOBAL_SNAPSHOT_CACHE_BACKUP"
        GLOBAL_SNAPSHOT_CACHE_HAD_FILE=1
    else
        : >"$GLOBAL_SNAPSHOT_CACHE_BACKUP"
        GLOBAL_SNAPSHOT_CACHE_HAD_FILE=0
    fi
}

restore_global_snapshot_cache() {
    [ -n "$GLOBAL_SNAPSHOT_CACHE_BACKUP" ] || return 0

    if [ "$GLOBAL_SNAPSHOT_CACHE_HAD_FILE" -eq 1 ]; then
        cp "$GLOBAL_SNAPSHOT_CACHE_BACKUP" "$GLOBAL_SNAPSHOT_CACHE"
    else
        rm -f "$GLOBAL_SNAPSHOT_CACHE"
    fi
}

cleanup_test_artifacts() {
    local pid path idx server runtime_dir
    restore_global_snapshot_cache
    for pid in "${SOCKET_PIDS[@]:-}"; do
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    for idx in "${!DAEMON_SERVERS[@]}"; do
        server="${DAEMON_SERVERS[$idx]}"
        runtime_dir="${DAEMON_RUNTIME_DIRS[$idx]:-}"
        env XDG_RUNTIME_DIR="$runtime_dir" \
            emacsclient -a false -s "$server" --eval "(kill-emacs)" >/dev/null 2>&1 || true
    done
    for path in "${TEMP_ARTIFACTS[@]:-}"; do
        rm -rf "$path" 2>/dev/null || true
    done
}

trap cleanup_test_artifacts EXIT

run_batch_bootstrap() {
    emacs --batch -Q \
        -L "$DIR" \
        -L "$DIR/lisp" \
        -L "$DIR/lisp/modules" \
        -L "$DIR/packages/gptel" \
        -L "$DIR/packages/gptel-agent" \
        -L "$DIR/tests" \
        -l "$DIR/tests/test-auto-workflow-batch.el" \
        -f test-auto-workflow-batch-run
}

start_fake_socket_owner() {
    local socket_path="$1"

    python3 - "$socket_path" <<'PY' &
import socket
import sys
import time
from pathlib import Path

path = Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
try:
    path.unlink()
except FileNotFoundError:
    pass

sock = socket.socket(socket.AF_UNIX)
sock.bind(str(path))
sock.listen(1)
try:
    time.sleep(30)
finally:
    sock.close()
    try:
        path.unlink()
    except FileNotFoundError:
        pass
PY

    local pid=$!
    SOCKET_PIDS+=("$pid")
    for _ in $(seq 1 50); do
        if [ -S "$socket_path" ]; then
            return 0
        fi
        sleep 0.1
    done
    echo "  ✗ fake socket did not appear: $socket_path"
    return 1
}

start_test_daemon() {
    local server_name="$1"
    local runtime_dir="$2"

    env -u DISPLAY -u WAYLAND_DISPLAY -u WAYLAND_SOCKET -u XAUTHORITY \
        XDG_RUNTIME_DIR="$runtime_dir" \
        emacs --init-directory="$DIR" --bg-daemon="$server_name" >/dev/null 2>&1 || true
    DAEMON_SERVERS+=("$server_name")
    DAEMON_RUNTIME_DIRS+=("$runtime_dir")

    for _ in $(seq 1 50); do
        if env XDG_RUNTIME_DIR="$runtime_dir" \
           emacsclient -a false -s "$server_name" --eval "t" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.2
    done

    echo "  ✗ test daemon did not start: $server_name"
    return 1
}

echo "=== Auto-Workflow E2E Test ==="
echo

echo "[1/11] Checking prerequisites..."
if [ ! -x "$RUNNER" ]; then
    echo "  ✗ wrapper missing or not executable: $RUNNER"
    exit 1
fi
echo "  ✓ wrapper exists: $RUNNER"

if ! command -v emacsclient >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/emacsclient ] && [ ! -x /usr/local/bin/emacsclient ]; then
    echo "  ✗ emacsclient not found"
    exit 1
fi
echo "  ✓ emacsclient is resolvable"

echo
echo "[2/11] Checking wrapper status..."
if "$RUNNER" status | grep -q ':phase'; then
    echo "  ✓ wrapper returns a workflow status snapshot"
else
    echo "  ✗ wrapper status did not return workflow data"
    exit 1
fi

echo
echo "[3/11] Checking persisted live snapshot handling..."
STATUS_TMP="$(mktemp "$DIR/var/tmp/cron/test-status-XXXXXX.sexp")"
MESSAGES_TMP="$(mktemp "$DIR/var/tmp/cron/test-messages-XXXXXX.txt")"
TEMP_ARTIFACTS+=("$STATUS_TMP" "$MESSAGES_TMP")
printf '%s\n' '(:running t :kept 2 :total 5 :phase "running" :run-id "2026-04-15T230002Z-2dbb" :results "var/tmp/experiments/2026-04-15T230002Z-2dbb/results.tsv")' >"$STATUS_TMP"
printf '%s\n' '[auto-workflow] reviewer still running...' >"$MESSAGES_TMP"
touch -d '2 minutes ago' "$STATUS_TMP"
if AUTO_WORKFLOW_STATUS_FILE="$STATUS_TMP" \
   AUTO_WORKFLOW_MESSAGES_FILE="$MESSAGES_TMP" \
   AUTO_WORKFLOW_EMACS_SERVER="missing-status-test-$$" \
   AUTO_WORKFLOW_ACTIVE_SNAPSHOT_TTL=45 \
   "$RUNNER" status | grep -q ':running t' &&
   grep -q ':running t' "$STATUS_TMP"; then
    echo "  ✓ fresh messages keep persisted running snapshot alive"
else
    echo "  ✗ stale status with fresh messages was not preserved"
    exit 1
fi

touch -d '2 minutes ago' "$MESSAGES_TMP"
XDG_RUNTIME_DIR_TMP="$(mktemp -d "$DIR/var/tmp/cron/test-xdg-runtime-XXXXXX")"
TEMP_ARTIFACTS+=("$XDG_RUNTIME_DIR_TMP")
XDG_SOCKET_SERVER="fake-status-test-xdg-$$"
XDG_SOCKET_PATH="$XDG_RUNTIME_DIR_TMP/emacs/$XDG_SOCKET_SERVER"
start_fake_socket_owner "$XDG_SOCKET_PATH"
if AUTO_WORKFLOW_STATUS_FILE="$STATUS_TMP" \
   AUTO_WORKFLOW_MESSAGES_FILE="$MESSAGES_TMP" \
   AUTO_WORKFLOW_EMACS_SERVER="$XDG_SOCKET_SERVER" \
   XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR_TMP" \
   AUTO_WORKFLOW_ACTIVE_SNAPSHOT_TTL=45 \
   "$RUNNER" status | grep -q ':running t' &&
   grep -q ':running t' "$STATUS_TMP"; then
    echo "  ✓ XDG runtime socket keeps persisted running snapshot alive"
else
    echo "  ✗ XDG runtime socket was not recognized"
    exit 1
fi

touch -d '2 minutes ago' "$STATUS_TMP"
touch -d '2 minutes ago' "$MESSAGES_TMP"
TMPDIR_SOCKET_ROOT="$(mktemp -d "$DIR/var/tmp/cron/test-tmpdir-runtime-XXXXXX")"
TEMP_ARTIFACTS+=("$TMPDIR_SOCKET_ROOT")
TMPDIR_SOCKET_SERVER="fake-status-test-tmp-$$"
TMPDIR_SOCKET_PATH="$TMPDIR_SOCKET_ROOT/emacs$(id -u)/$TMPDIR_SOCKET_SERVER"
start_fake_socket_owner "$TMPDIR_SOCKET_PATH"
if env -u XDG_RUNTIME_DIR \
   AUTO_WORKFLOW_STATUS_FILE="$STATUS_TMP" \
   AUTO_WORKFLOW_MESSAGES_FILE="$MESSAGES_TMP" \
   AUTO_WORKFLOW_EMACS_SERVER="$TMPDIR_SOCKET_SERVER" \
   TMPDIR="$TMPDIR_SOCKET_ROOT" \
   AUTO_WORKFLOW_ACTIVE_SNAPSHOT_TTL=45 \
   "$RUNNER" status | grep -q ':running t' &&
   grep -q ':running t' "$STATUS_TMP"; then
    echo "  ✓ TMPDIR socket keeps persisted running snapshot alive"
else
    echo "  ✗ TMPDIR socket was not recognized"
    exit 1
fi

echo
echo "[4/11] Checking daemon completion overrides stale running snapshot..."
COMPLETE_RUNTIME_DIR="$(mktemp -d "$DIR/var/tmp/cron/test-complete-runtime-XXXXXX")"
TEMP_ARTIFACTS+=("$COMPLETE_RUNTIME_DIR")
COMPLETE_SERVER="complete-status-test-$$"
start_test_daemon "$COMPLETE_SERVER" "$COMPLETE_RUNTIME_DIR"
printf '%s\n' '(:running t :kept 0 :total 5 :phase "running" :run-id "stale-complete" :results "var/tmp/experiments/stale-complete/results.tsv")' >"$STATUS_TMP"
printf '%s\n' '[auto-workflow] stale running snapshot' >"$MESSAGES_TMP"
env XDG_RUNTIME_DIR="$COMPLETE_RUNTIME_DIR" \
    emacsclient -a false -s "$COMPLETE_SERVER" --eval \
    "(progn
       (load-file \"$DIR/lisp/modules/gptel-tools-agent.el\")
       (setq gptel-auto-workflow--stats '(:phase \"complete\" :total 5 :kept 0)
             gptel-auto-workflow--running nil
             gptel-auto-workflow--run-id nil
             gptel-auto-workflow--current-target nil
             gptel-auto-workflow--current-project nil)
       t)" >/dev/null
if AUTO_WORKFLOW_STATUS_FILE="$STATUS_TMP" \
   AUTO_WORKFLOW_MESSAGES_FILE="$MESSAGES_TMP" \
   AUTO_WORKFLOW_EMACS_SERVER="$COMPLETE_SERVER" \
   XDG_RUNTIME_DIR="$COMPLETE_RUNTIME_DIR" \
   AUTO_WORKFLOW_ACTIVE_SNAPSHOT_TTL=45 \
   "$RUNNER" status | grep -q ':phase "complete"' &&
   grep -q ':phase "complete"' "$STATUS_TMP" &&
   ! grep -q ':running t' "$STATUS_TMP"; then
    echo "  ✓ live daemon completion overrides stale persisted running state"
else
    echo "  ✗ wrapper kept stale running snapshot after daemon completion"
    exit 1
fi

echo
echo "[5/11] Checking live daemon messages refresh stale persisted tail..."
LIVE_MESSAGES_RUNTIME_DIR="$(mktemp -d "$DIR/var/tmp/cron/test-live-messages-runtime-XXXXXX")"
TEMP_ARTIFACTS+=("$LIVE_MESSAGES_RUNTIME_DIR")
LIVE_MESSAGES_SERVER="live-messages-test-$$"
start_test_daemon "$LIVE_MESSAGES_SERVER" "$LIVE_MESSAGES_RUNTIME_DIR"
printf '%s\n' '(:running t :kept 0 :total 3 :phase "running" :run-id "live-messages" :results "var/tmp/experiments/live-messages/results.tsv")' >"$STATUS_TMP"
printf '%s\n' '[auto-workflow] stale persisted tail' >"$MESSAGES_TMP"
touch -d '2 minutes ago' "$MESSAGES_TMP"
env XDG_RUNTIME_DIR="$LIVE_MESSAGES_RUNTIME_DIR" \
    emacsclient -a false -s "$LIVE_MESSAGES_SERVER" --eval \
    "(progn
       (load-file \"$DIR/lisp/modules/gptel-tools-agent.el\")
       (setq gptel-auto-workflow--stats '(:phase \"running\" :total 3 :kept 0)
             gptel-auto-workflow--running t
             gptel-auto-workflow--run-id \"live-messages\"
             gptel-auto-workflow--current-target \"lisp/modules/gptel-agent-loop.el\")
       (with-current-buffer (get-buffer-create \"*Messages*\")
         (let ((inhibit-read-only t))
           (goto-char (point-max))
           (insert \"[auto-workflow] live daemon message sentinel\\n\")))
       t)" >/dev/null
if AUTO_WORKFLOW_STATUS_FILE="$STATUS_TMP" \
   AUTO_WORKFLOW_MESSAGES_FILE="$MESSAGES_TMP" \
   AUTO_WORKFLOW_EMACS_SERVER="$LIVE_MESSAGES_SERVER" \
   XDG_RUNTIME_DIR="$LIVE_MESSAGES_RUNTIME_DIR" \
   AUTO_WORKFLOW_ACTIVE_SNAPSHOT_TTL=45 \
   "$RUNNER" messages | grep -q 'live daemon message sentinel' &&
   grep -q 'live daemon message sentinel' "$MESSAGES_TMP" &&
   ! grep -q 'stale persisted tail' "$MESSAGES_TMP"; then
    echo "  ✓ live daemon messages override stale persisted tail"
else
    echo "  ✗ wrapper kept stale persisted messages while daemon was active"
    exit 1
fi

echo
echo
echo "[6/11] Checking override isolation..."
backup_global_snapshot_cache
CACHE_STATUS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aw-status-dirXXXXXX")"
TEMP_ARTIFACTS+=("$CACHE_STATUS_DIR")
CACHE_STATUS_FILE="$CACHE_STATUS_DIR/auto-workflow-status.sexp"
printf '%s\n' '(:running t :kept 1 :total 1 :phase "running" :run-id "cache-test" :results "var/tmp/experiments/cache-test/results.tsv")' >"$CACHE_STATUS_FILE"
if AUTO_WORKFLOW_STATUS_FILE="$CACHE_STATUS_FILE" \
   AUTO_WORKFLOW_EMACS_SERVER="missing-cache-test-$$" \
   "$RUNNER" status >/dev/null &&
   if [ "$GLOBAL_SNAPSHOT_CACHE_HAD_FILE" -eq 1 ]; then
       cmp -s "$GLOBAL_SNAPSHOT_CACHE" "$GLOBAL_SNAPSHOT_CACHE_BACKUP"
   else
       [ ! -e "$GLOBAL_SNAPSHOT_CACHE" ]
   fi; then
    echo "  ✓ temporary status overrides do not rewrite the shared snapshot cache"
else
    echo "  ✗ temporary status overrides rewrote the shared snapshot cache"
    if [ -e "$GLOBAL_SNAPSHOT_CACHE" ]; then
        sed 's/^/    /' "$GLOBAL_SNAPSHOT_CACHE"
    fi
    exit 1
fi

echo
echo "[7/11] Checking required modules..."
for module in gptel-tools-agent.el gptel-auto-workflow-projects.el gptel-auto-workflow-strategic.el; do
    if [ -f "lisp/modules/$module" ]; then
        echo "  ✓ $module exists"
    else
        echo "  ✗ $module missing"
        exit 1
    fi
done

echo
echo "[8/11] Checking cron configuration..."
if crontab -l 2>/dev/null | grep -Eq '^[0-9*@].*run-auto-workflow-cron\.sh auto-workflow'; then
    echo "  ✓ Auto-workflow cron job installed via wrapper"
    crontab -l | grep -E '^[0-9*@].*run-auto-workflow-cron\.sh auto-workflow' | head -1 | sed 's/^/    /'
else
    echo "  ✗ Wrapper-based auto-workflow cron job not found"
    echo "    Run: ./scripts/install-cron.sh"
    exit 1
fi

echo
echo "[9/11] Checking required directories..."
for dir in var/tmp/cron var/tmp/experiments; do
    if [ -d "$dir" ]; then
        echo "  ✓ $dir exists"
    else
        echo "  ⚠ $dir missing, creating..."
        mkdir -p "$dir"
    fi
done

echo
echo "[10/11] Testing batch module loading..."
if run_batch_bootstrap >/dev/null 2>&1; then
    echo "  ✓ auto-workflow modules load successfully in batch mode"
else
    echo "  ✗ Failed to load auto-workflow modules in batch mode"
    exit 1
fi

echo
echo "[11/11] Checking workflow entrypoints..."
if "$RUNNER" status | grep -q ':phase'; then
    echo "  ✓ wrapper status remains responsive"
else
    echo "  ✗ wrapper status did not return workflow data"
    exit 1
fi

echo
echo "=== All E2E Tests Passed ==="
echo
echo "Next steps:"
echo "1. Test manual run: ./scripts/run-auto-workflow-cron.sh auto-workflow"
echo "2. Inspect status/output: ./scripts/run-auto-workflow-cron.sh status && ./scripts/run-auto-workflow-cron.sh messages"
echo "3. Check logs: tail -f var/tmp/cron/auto-workflow.log"
