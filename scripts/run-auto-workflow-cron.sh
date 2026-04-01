#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION="${1:-auto-workflow}"
shift || true

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

EMACSCLIENT="$(resolve_emacsclient)" || {
    echo "emacsclient not found" >&2
    exit 1
}

ROOT_LISP=$(printf '%s' "$DIR" | sed 's/\\/\\\\/g; s/"/\\"/g')

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
EMACS_ARGS=(-a '')
if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "${XDG_RUNTIME_DIR}/emacs/server" ]; then
    EMACS_ARGS+=(-s "${XDG_RUNTIME_DIR}/emacs/server")
elif [ -S "/run/user/$(id -u)/emacs/server" ]; then
    EMACS_ARGS+=(-s "/run/user/$(id -u)/emacs/server")
fi

exec "$EMACSCLIENT" "${EMACS_ARGS[@]}" --eval "$ELISP"
