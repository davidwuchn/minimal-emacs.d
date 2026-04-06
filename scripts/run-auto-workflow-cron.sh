#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION="${1:-auto-workflow}"
shift || true
SERVER_NAME="${AUTO_WORKFLOW_EMACS_SERVER:-copilot-auto-workflow}"
STATUS_FILE="$DIR/var/tmp/cron/auto-workflow-status.sexp"
DAEMON_LOG="$DIR/var/tmp/cron/auto-workflow-daemon.log"

resolve_emacsclient() {
    if command -v emacsclient >/dev/null 2>&1; then
        command -v emacsclient
        return
    fi
    if [ -x /opt/homebrew/bin/emacsclient ]; then
        echo /opt/homebrew/bin/emacsclient
        return
    fi
    if [ -x /usr/local/bin/emacsclient ]; then
        echo /usr/local/bin/emacsclient
        return
    fi
    return 1
}

resolve_emacs() {
    if command -v emacs >/dev/null 2>&1; then
        command -v emacs
        return
    fi
    if [ -x /opt/homebrew/bin/emacs ]; then
        echo /opt/homebrew/bin/emacs
        return
    fi
    if [ -x /usr/local/bin/emacs ]; then
        echo /usr/local/bin/emacs
        return
    fi
    if [ -x /Applications/Emacs.app/Contents/MacOS/Emacs ]; then
        echo /Applications/Emacs.app/Contents/MacOS/Emacs
        return
    fi
    return 1
}

EMACSCLIENT="$(resolve_emacsclient)" || {
    echo "emacsclient not found" >&2
    exit 1
}

EMACS="$(resolve_emacs)" || {
    echo "emacs not found" >&2
    exit 1
}

ROOT_LISP=$(printf '%s' "$DIR" | sed 's/\\/\\\\/g; s/"/\\"/g')
mkdir -p "$DIR/var/tmp/cron" "$DIR/var/tmp/experiments"

default_status() {
    printf '(:running nil :kept 0 :total 0 :phase "idle" :results "var/tmp/experiments/%s/results.tsv")\n' "$(date +%F)"
}

print_status() {
    if [ -s "$STATUS_FILE" ]; then
        cat "$STATUS_FILE"
    else
        default_status
    fi
}

status_indicates_running() {
    [ -r "$STATUS_FILE" ] && grep -q ':running t' "$STATUS_FILE"
}

run_emacsclient_eval() {
    local elisp="$1"
    local timeout="${2:-10}"
    python3 - "$EMACSCLIENT" "$SERVER_NAME" "$elisp" "$timeout" <<'PY'
import subprocess
import sys

emacsclient, server_name, elisp, timeout = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
try:
    proc = subprocess.run(
        [emacsclient, "-s", server_name, "--eval", elisp],
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )
except subprocess.TimeoutExpired as err:
    if err.stdout:
        sys.stdout.write(err.stdout if isinstance(err.stdout, str) else err.stdout.decode())
    if err.stderr:
        sys.stderr.write(err.stderr if isinstance(err.stderr, str) else err.stderr.decode())
    raise SystemExit(124)

sys.stdout.write(proc.stdout)
sys.stderr.write(proc.stderr)
raise SystemExit(proc.returncode)
PY
}

check_worker_daemon() {
    if run_emacsclient_eval "t" 1 >/dev/null 2>&1; then
        return 0
    fi
    local rc=$?
    if [ "$rc" -eq 124 ]; then
        return 2
    fi
    return 1
}

ensure_worker_daemon() {
    if check_worker_daemon; then
        return 0
    fi
    local rc=$?
    if [ "$rc" -eq 2 ]; then
        return 0
    fi
    MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 "$EMACS" --bg-daemon="$SERVER_NAME" >>"$DAEMON_LOG" 2>&1 || true
    for _ in $(seq 1 50); do
        if check_worker_daemon; then
            return 0
        fi
        rc=$?
        if [ "$rc" -eq 2 ]; then
            return 0
        fi
        sleep 0.2
    done
    echo "failed to start worker daemon: $SERVER_NAME" >&2
    tail -n 40 "$DAEMON_LOG" >&2 || true
    return 1
}

case "$ACTION" in
    auto-workflow)
        ELISP="(let ((root \"$ROOT_LISP\")) (load-file (expand-file-name \"lisp/modules/gptel-tools-agent.el\" root)) (load-file (expand-file-name \"lisp/modules/gptel-auto-workflow-strategic.el\" root)) (load-file (expand-file-name \"lisp/modules/gptel-auto-workflow-projects.el\" root)) (gptel-auto-workflow-queue-all-projects))"
        ;;
    research)
        ELISP="(let ((root \"$ROOT_LISP\")) (load-file (expand-file-name \"lisp/modules/gptel-tools-agent.el\" root)) (load-file (expand-file-name \"lisp/modules/gptel-auto-workflow-strategic.el\" root)) (load-file (expand-file-name \"lisp/modules/gptel-auto-workflow-projects.el\" root)) (gptel-auto-workflow-queue-all-research))"
        ;;
    mementum)
        ELISP="(let ((root \"$ROOT_LISP\")) (load-file (expand-file-name \"lisp/modules/gptel-tools-agent.el\" root)) (load-file (expand-file-name \"lisp/modules/gptel-auto-workflow-projects.el\" root)) (gptel-auto-workflow-queue-all-mementum))"
        ;;
    instincts)
        ELISP="(let ((root \"$ROOT_LISP\")) (load-file (expand-file-name \"lisp/modules/gptel-tools-agent.el\" root)) (load-file (expand-file-name \"lisp/modules/gptel-auto-workflow-projects.el\" root)) (gptel-auto-workflow-queue-all-instincts))"
        ;;
    status)
        ELISP="(let ((root \"$ROOT_LISP\")) (load-file (expand-file-name \"lisp/modules/gptel-tools-agent.el\" root)) (gptel-auto-workflow-status))"
        ;;
    *)
        echo "Usage: $0 {auto-workflow|research|mementum|instincts|status}" >&2
        exit 2
        ;;
esac

cd "$DIR"
if [ "$ACTION" = "status" ]; then
    print_status
    exit 0
fi

if status_indicates_running; then
    echo "already-running"
    exit 0
fi

ensure_worker_daemon

if status_indicates_running; then
    echo "already-running"
    exit 0
fi

if run_emacsclient_eval "$ELISP" 10; then
    exit 0
fi

rc=$?
if [ "$rc" -eq 124 ] && status_indicates_running; then
    echo "already-running"
    exit 0
fi

exit "$rc"
