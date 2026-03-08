#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMACS=${EMACS:-emacs}
ITERATIONS=${1:-200}

"$EMACS" --batch -Q \
  -L "$DIR" \
  -L "$DIR/lisp" \
  -L "$DIR/lisp/modules" \
  --eval "(progn
    (require 'gptel-programmatic-benchmark)
    (gptel-programmatic-benchmark-print-report ${ITERATIONS}))"
