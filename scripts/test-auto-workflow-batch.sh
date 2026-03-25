#!/usr/bin/env bash

# test-auto-workflow-batch.sh
# Run auto-workflow in batch mode to verify full pipeline.
#
# Usage:
#   ./scripts/test-auto-workflow-batch.sh

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "=== Auto-Workflow Batch Test ==="
echo "Directory: $DIR"
echo "Time: $(date)"
echo ""

# Run in batch mode
emacs -Q --batch \
    -l "$DIR/early-init.el" \
    --eval "(progn
      (setq package-archives nil)
      (package-initialize 'no-activate)
      (let ((elpa-dir (expand-file-name \"var/elpa\" \"$DIR\")))
        ;; Add all package directories to load-path
        (dolist (f (directory-files elpa-dir t \"^[^.]\" t))
          (when (file-directory-p f)
            (add-to-list 'load-path f))))
      (add-to-list 'load-path (expand-file-name \"lisp\" \"$DIR\"))
      (add-to-list 'load-path (expand-file-name \"lisp/modules\" \"$DIR\"))
      (add-to-list 'load-path (expand-file-name \"packages/ai-code\" \"$DIR\"))
      (add-to-list 'load-path (expand-file-name \"packages/gptel-agent\" \"$DIR\"))
      (setq user-emacs-directory \"$DIR/\"))" \
    -l "$DIR/scripts/test-auto-workflow-batch.el" \
    -f test-auto-workflow-batch-run \
    2>&1

echo ""
echo "=== Checking Results ==="
echo ""

# Check for pushed branches
echo "Fetching remote..."
git fetch origin 2>/dev/null || true

echo ""
echo "Remote optimize branches:"
git branch -r 2>/dev/null | grep optimize || echo "No optimize branches on remote"

echo ""
echo "Local optimize branches:"
git branch 2>/dev/null | grep optimize || echo "No local optimize branches"

echo ""
echo "Worktrees:"
git worktree list | grep optimize || echo "No active worktrees"

echo ""
echo "Results files:"
find var/tmp/experiments -name "results.tsv" 2>/dev/null | while read f; do
    echo "--- $f ---"
    cat "$f"
done || echo "No results files"

echo ""
echo "=== Done ==="