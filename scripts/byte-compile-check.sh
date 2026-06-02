#!/usr/bin/env bash
# Byte-compile check for experiment validation.
# Uses project load-path so require dependencies resolve.
# Usage: scripts/byte-compile-check.sh <file.el>
# Returns 0 if clean, 1 if errors.

set -euo pipefail
FILE="$1"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

emacs --batch \
  -L "$DIR/lisp" \
  -L "$DIR/lisp/modules" \
  -L "$DIR/packages/gptel" \
  -L "$DIR/packages/gptel-agent" \
  -L "$DIR/packages/nucleus" \
  -L "$DIR/packages/mementum" \
  -L "$DIR/packages/ai-code" \
  --eval "(let ((elpa-dir \"$DIR/var/elpa\")) (when (file-directory-p elpa-dir) (dolist (entry (directory-files elpa-dir t \"^[^.]\")) (when (file-directory-p entry) (add-to-list 'load-path entry)))))" \
  -f batch-byte-compile \
  "$FILE" 2>/dev/null
