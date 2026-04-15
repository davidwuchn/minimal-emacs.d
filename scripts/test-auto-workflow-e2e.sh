#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$DIR/scripts/run-auto-workflow-cron.sh"
cd "$DIR"

SOCKET_PIDS=()
TEMP_ARTIFACTS=()

cleanup_test_artifacts() {
    local pid path
    for pid in "${SOCKET_PIDS[@]:-}"; do
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
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

echo "=== Auto-Workflow E2E Test ==="
echo

echo "[1/8] Checking prerequisites..."
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
echo "[2/8] Checking wrapper status..."
if "$RUNNER" status | grep -q ':phase'; then
    echo "  ✓ wrapper returns a workflow status snapshot"
else
    echo "  ✗ wrapper status did not return workflow data"
    exit 1
fi

echo
echo "[3/8] Checking persisted live snapshot handling..."
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
echo "[4/8] Checking required modules..."
for module in gptel-tools-agent.el gptel-auto-workflow-projects.el gptel-auto-workflow-strategic.el; do
    if [ -f "lisp/modules/$module" ]; then
        echo "  ✓ $module exists"
    else
        echo "  ✗ $module missing"
        exit 1
    fi
done

echo
echo "[5/8] Checking cron configuration..."
if crontab -l 2>/dev/null | grep -Eq '^[0-9*@].*run-auto-workflow-cron\.sh auto-workflow'; then
    echo "  ✓ Auto-workflow cron job installed via wrapper"
    crontab -l | grep -E '^[0-9*@].*run-auto-workflow-cron\.sh auto-workflow' | head -1 | sed 's/^/    /'
else
    echo "  ✗ Wrapper-based auto-workflow cron job not found"
    echo "    Run: ./scripts/install-cron.sh"
    exit 1
fi

echo
echo "[6/8] Checking required directories..."
for dir in var/tmp/cron var/tmp/experiments; do
    if [ -d "$dir" ]; then
        echo "  ✓ $dir exists"
    else
        echo "  ⚠ $dir missing, creating..."
        mkdir -p "$dir"
    fi
done

echo
echo "[7/8] Testing batch module loading..."
if run_batch_bootstrap >/dev/null 2>&1; then
    echo "  ✓ auto-workflow modules load successfully in batch mode"
else
    echo "  ✗ Failed to load auto-workflow modules in batch mode"
    exit 1
fi

echo
echo "[8/8] Checking workflow entrypoints..."
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
