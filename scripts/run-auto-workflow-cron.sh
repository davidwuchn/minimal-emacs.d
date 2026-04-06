#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION="${1:-auto-workflow}"
shift || true

if command -v emacsclient >/dev/null 2>&1; then
    EMACSCLIENT="$(command -v emacsclient)"
elif [ -x /opt/homebrew/bin/emacsclient ]; then
    EMACSCLIENT=/opt/homebrew/bin/emacsclient
elif [ -x /usr/local/bin/emacsclient ]; then
    EMACSCLIENT=/usr/local/bin/emacsclient
else
    echo "emacsclient not found" >&2
    exit 1
fi

case "$ACTION" in
    auto-workflow)
        ELISP='(progn
                 (load-file "~/.emacs.d/lisp/modules/gptel-auto-workflow-projects.el")
                 (gptel-auto-workflow-run-all-projects))'
        ;;
    research)
        ELISP='(progn
                 (load-file "~/.emacs.d/lisp/modules/gptel-auto-workflow-projects.el")
                 (load-file "~/.emacs.d/lisp/modules/gptel-auto-workflow-strategic.el")
                 (gptel-auto-workflow-run-all-research))'
        ;;
    mementum)
        ELISP='(progn
                 (load-file "~/.emacs.d/lisp/modules/gptel-auto-workflow-projects.el")
                 (gptel-auto-workflow-run-all-mementum))'
        ;;
    instincts)
        ELISP='(progn
                 (load-file "~/.emacs.d/lisp/modules/gptel-auto-workflow-projects.el")
                 (gptel-auto-workflow-run-all-instincts))'
        ;;
    status)
        ELISP='(progn
                 (load-file "~/.emacs.d/lisp/modules/gptel-tools-agent.el")
                 (gptel-auto-workflow-status))'
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
fi

exec "$EMACSCLIENT" "${EMACS_ARGS[@]}" --eval "$ELISP"
