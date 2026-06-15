#!/usr/bin/env bash
# Pipeline: Research -> Digestion -> Auto-Workflow
# Thin POSIX wrapper that delegates to the babashka orchestrator.
# All logic lives in clj/ov5/pipeline.clj (executed via bb -m ov5.pipeline).

set -euo pipefail

# Prevent C stack overflow in deeply nested subagent calls
ulimit -s 65532 2>/dev/null || true

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pin TMPDIR to /tmp so emacsclient finds the daemon socket.
export TMPDIR=/tmp

# Resolve babashka (bb).  Cron's PATH typically omits the user's mise/asdf
# shims, so `bb` is not found even though it is installed — the pipeline
# silently died with "exec: bb: not found".  Probe PATH first, then the
# common mise/asdf/Homebrew shim locations.
resolve_bb() {
    local c
    for c in \
        "$(command -v bb 2>/dev/null)" \
        "$HOME/.local/share/mise/shims/bb" \
        "$HOME/.asdf/shims/bb" \
        "$HOME/.local/bin/bb" \
        "$(ls "$HOME"/.local/share/mise/installs/babashka/*/bb 2>/dev/null | head -1)" \
        "/opt/homebrew/bin/bb" \
        "/usr/local/bin/bb"; do
        [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
    done
    return 1
}

BB_BIN="$(resolve_bb)" || {
    echo "[pipeline] FATAL: babashka (bb) not found on PATH or in common" \
         "mise/asdf/homebrew locations. Install bb or add its shim dir to" \
         "PATH in the crontab." >&2
    exit 127
}

cd "$DIR" && exec "$BB_BIN" -m ov5.pipeline "$@"
