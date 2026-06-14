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

cd "$DIR" && exec bb -m ov5.pipeline "$@"
