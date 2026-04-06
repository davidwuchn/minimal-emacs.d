#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION="${1:-auto-workflow}"
shift || true
SERVER_NAME="${AUTO_WORKFLOW_EMACS_SERVER:-copilot-auto-workflow}"
STATUS_FILE="${AUTO_WORKFLOW_STATUS_FILE:-$DIR/var/tmp/cron/auto-workflow-status.sexp}"
DAEMON_LOG="$DIR/var/tmp/cron/auto-workflow-daemon.log"
MESSAGES_FILE="${AUTO_WORKFLOW_MESSAGES_FILE:-$DIR/var/tmp/cron/auto-workflow-messages-tail.txt}"
MESSAGES_CHARS="${AUTO_WORKFLOW_MESSAGES_CHARS:-16000}"

lisp_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

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

ROOT_LISP=$(lisp_escape "$DIR")
MESSAGES_LISP=$(lisp_escape "$MESSAGES_FILE")
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

rewrite_status_idle() {
    if [ ! -s "$STATUS_FILE" ]; then
        default_status >"$STATUS_FILE"
        return 0
    fi

    python3 - "$STATUS_FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = re.sub(r':running\s+t', ':running nil', text, count=1)
text = re.sub(r':phase\s+"[^"]*"', ':phase "idle"', text, count=1)
if not text.endswith("\n"):
    text += "\n"
path.write_text(text, encoding="utf-8")
PY
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

clear_stale_running_status() {
    if ! status_indicates_running; then
        return 0
    fi

    local rc
    if check_worker_daemon; then
        rc=0
    else
        rc=$?
    fi

    if [ "$rc" -eq 0 ]; then
        return 0
    fi

    if [ "$rc" -eq 1 ]; then
        rewrite_status_idle
    fi
    return 0
}

wrap_emacs_eval() {
    local body="$1"
    local env_elisp=""
    local ssh_auth_sock="${SSH_AUTH_SOCK:-}"
    local git_ssh_command="${GIT_SSH_COMMAND:-}"

    if [ -n "$ssh_auth_sock" ]; then
        env_elisp="$env_elisp (setenv \"SSH_AUTH_SOCK\" \"$(lisp_escape "$ssh_auth_sock")\")"
    fi

    if [ -z "$git_ssh_command" ] && [ "$(uname -s)" = "Darwin" ] && [ -n "$ssh_auth_sock" ]; then
        git_ssh_command='ssh -o BatchMode=yes -o IdentitiesOnly=yes -o UseKeychain=yes -o AddKeysToAgent=yes'
    fi

    if [ -n "$git_ssh_command" ]; then
        env_elisp="$env_elisp (setenv \"GIT_SSH_COMMAND\" \"$(lisp_escape "$git_ssh_command")\")"
    fi

    printf '(with-current-buffer (get-buffer-create "*copilot-auto-workflow-eval*")%s %s)' \
           "$env_elisp" "$body"
}

ensure_worker_daemon() {
    local rc
    if check_worker_daemon; then
        rc=0
    else
        rc=$?
    fi

    if [ "$rc" -eq 0 ]; then
        return 0
    fi
    if [ "$rc" -eq 2 ]; then
        return 0
    fi
    MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 "$EMACS" --bg-daemon="$SERVER_NAME" >>"$DAEMON_LOG" 2>&1 || true
    for _ in $(seq 1 50); do
        if check_worker_daemon; then
            rc=0
        else
            rc=$?
        fi

        if [ "$rc" -eq 0 ]; then
            return 0
        fi
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
        ELISP="(let ((root \"$ROOT_LISP\"))
                 (setq user-emacs-directory root)
                 (defvar gptel--tool-preview-alist nil)
                 (load-file (expand-file-name \"lisp/modules/nucleus-tools.el\" root))
                 (load-file (expand-file-name \"lisp/modules/nucleus-prompts.el\" root))
                 (load-file (expand-file-name \"lisp/modules/nucleus-presets.el\" root))
                 (when (fboundp 'nucleus--register-gptel-directives)
                   (nucleus--register-gptel-directives))
                 (when (fboundp 'nucleus--override-gptel-agent-presets)
                   (nucleus--override-gptel-agent-presets))
                 (require 'gptel)
                 (unless (fboundp 'gptel--format-tool-call)
                   (defun gptel--format-tool-call (name arg-values)
                     (format \"(%s %s)\n\"
                             (propertize (or name \"unknown\") 'font-lock-face 'font-lock-keyword-face)
                             (propertize (format \"%s\" arg-values) 'font-lock-face 'font-lock-string-face))))
                 (require 'gptel-request)
                 (require 'gptel-agent-tools)
                 (load-file (expand-file-name \"lisp/modules/gptel-tools-agent.el\" root))
                 (load-file (expand-file-name \"lisp/modules/gptel-auto-workflow-strategic.el\" root))
                 (load-file (expand-file-name \"lisp/modules/gptel-auto-workflow-projects.el\" root))
                 (gptel-auto-workflow-queue-all-projects))"
        ;;
    research)
        ELISP="(let ((root \"$ROOT_LISP\"))
                 (setq user-emacs-directory root)
                 (defvar gptel--tool-preview-alist nil)
                 (load-file (expand-file-name \"lisp/modules/nucleus-tools.el\" root))
                 (load-file (expand-file-name \"lisp/modules/nucleus-prompts.el\" root))
                 (load-file (expand-file-name \"lisp/modules/nucleus-presets.el\" root))
                 (when (fboundp 'nucleus--register-gptel-directives)
                   (nucleus--register-gptel-directives))
                 (when (fboundp 'nucleus--override-gptel-agent-presets)
                   (nucleus--override-gptel-agent-presets))
                 (require 'gptel)
                 (unless (fboundp 'gptel--format-tool-call)
                   (defun gptel--format-tool-call (name arg-values)
                     (format \"(%s %s)\n\"
                             (propertize (or name \"unknown\") 'font-lock-face 'font-lock-keyword-face)
                             (propertize (format \"%s\" arg-values) 'font-lock-face 'font-lock-string-face))))
                 (require 'gptel-request)
                 (require 'gptel-agent-tools)
                 (load-file (expand-file-name \"lisp/modules/gptel-tools-agent.el\" root))
                 (load-file (expand-file-name \"lisp/modules/gptel-auto-workflow-strategic.el\" root))
                 (load-file (expand-file-name \"lisp/modules/gptel-auto-workflow-projects.el\" root))
                 (gptel-auto-workflow-queue-all-research))"
        ;;
    mementum)
        ELISP="(let ((root \"$ROOT_LISP\"))
                 (defvar gptel--tool-preview-alist nil)
                 (require 'gptel)
                 (unless (fboundp 'gptel--format-tool-call)
                   (defun gptel--format-tool-call (name arg-values)
                     (format \"(%s %s)\n\"
                             (propertize (or name \"unknown\") 'font-lock-face 'font-lock-keyword-face)
                             (propertize (format \"%s\" arg-values) 'font-lock-face 'font-lock-string-face))))
                 (load-file (expand-file-name \"lisp/modules/gptel-tools-agent.el\" root))
                 (load-file (expand-file-name \"lisp/modules/gptel-auto-workflow-projects.el\" root))
                 (gptel-auto-workflow-queue-all-mementum))"
        ;;
    instincts)
        ELISP="(let ((root \"$ROOT_LISP\"))
                 (defvar gptel--tool-preview-alist nil)
                 (require 'gptel)
                 (unless (fboundp 'gptel--format-tool-call)
                   (defun gptel--format-tool-call (name arg-values)
                     (format \"(%s %s)\n\"
                             (propertize (or name \"unknown\") 'font-lock-face 'font-lock-keyword-face)
                             (propertize (format \"%s\" arg-values) 'font-lock-face 'font-lock-string-face))))
                 (load-file (expand-file-name \"lisp/modules/gptel-tools-agent.el\" root))
                 (load-file (expand-file-name \"lisp/modules/gptel-auto-workflow-projects.el\" root))
                 (gptel-auto-workflow-queue-all-instincts))"
        ;;
    status)
        ELISP="(let ((root \"$ROOT_LISP\"))
                 (defvar gptel--tool-preview-alist nil)
                 (require 'gptel)
                 (unless (fboundp 'gptel--format-tool-call)
                   (defun gptel--format-tool-call (name arg-values)
                     (format \"(%s %s)\n\"
                             (propertize (or name \"unknown\") 'font-lock-face 'font-lock-keyword-face)
                             (propertize (format \"%s\" arg-values) 'font-lock-face 'font-lock-string-face))))
                  (load-file (expand-file-name \"lisp/modules/gptel-tools-agent.el\" root))
                  (gptel-auto-workflow-status))"
        ;;
    messages)
        ELISP="(let ((outfile \"$MESSAGES_LISP\")
                     (max-chars $MESSAGES_CHARS))
                 (with-current-buffer (get-buffer-create \"*Messages*\")
                   (write-region (max (point-min) (- (point-max) max-chars))
                                 (point-max)
                                 outfile nil 'silent))
                 outfile)"
        ;;
    *)
        echo "Usage: $0 {auto-workflow|research|mementum|instincts|status|messages}" >&2
        exit 2
        ;;
esac

EVAL_ELISP="$(wrap_emacs_eval "$ELISP")"

cd "$DIR"
if [ "$ACTION" = "status" ]; then
    clear_stale_running_status
    print_status
    exit 0
fi

if [ "$ACTION" = "messages" ]; then
    ensure_worker_daemon
    if run_emacsclient_eval "$EVAL_ELISP" 10 >/dev/null; then
        if [ -r "$MESSAGES_FILE" ]; then
            cat "$MESSAGES_FILE"
        fi
        exit 0
    fi
    exit $?
fi

clear_stale_running_status

if status_indicates_running; then
    echo "already-running"
    exit 0
fi

ensure_worker_daemon

if status_indicates_running; then
    echo "already-running"
    exit 0
fi

if run_emacsclient_eval "$EVAL_ELISP" 10; then
    exit 0
fi

rc=$?
if [ "$rc" -eq 124 ] && status_indicates_running; then
    echo "already-running"
    exit 0
fi

exit "$rc"
