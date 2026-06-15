#!/usr/bin/env bash
# TDD test for pre-commit paren-nesting detection hook.
# Tests that the hook blocks commits of files where defun/cl-defun/etc.
# are accidentally nested inside other defun bodies (the 3d8cc17cd bug).
#
# The 3d8cc17cd bug was: a function had its closing paren structure
# corrupted. The defun body had too many/few closes so the END of the
# defun was misplaced, causing the NEXT defun to be swallowed INSIDE.
# In effect: TWO top-level defuns became ONE nested defun.
#
# Run with: bash tests/test-pre-commit-paren-nesting.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRE_COMMIT_SOURCE="$REPO_ROOT/scripts/git-hooks/pre-commit"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"

# Install the tracked pre-commit hook
cp "$PRE_COMMIT_SOURCE" .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# Set env vars so hook skips submodule sync in temp repo
export VERIFY_NUCLEUS_SKIP_SUBMODULE_SYNC=1

COMMIT="git -c core.hooksPath=.git/hooks commit"

# ─── Test 1: nested defun at column 0 (the 3d8cc17cd bug) ───
echo "[test 1/2] pre-commit hook should block defun nested at column 0"
mkdir -p lisp/modules
cat > lisp/modules/nested-test.el << 'NESTED_EOF'
;;; nested-test.el --- Defun nested at column 0 (regression for 3d8cc17cd) -*- lexical-binding: t; -*-

(defun gptel-auto-experiment--outer-function ()
"Outer function with inner defun at column 0 — should be caught."
(defun gptel-auto-experiment--inner-function ()
"Defun at column 0 INSIDE the outer one — this is the 3d8cc17cd bug."
1))

(provide 'nested-test)
;;; nested-test.el ends here
NESTED_EOF

git add lisp/modules/nested-test.el
if $COMMIT -m "test nested defun" >commit1.log 2>&1; then
    echo "FAIL: pre-commit hook allowed commit of nested defun"
    cat commit1.log
    exit 1
fi
if ! grep -qi "nested\|top-level" commit1.log; then
    echo "FAIL: hook did not report nested-defun error (got: $(cat commit1.log))"
    exit 1
fi
echo "PASS: pre-commit hook correctly blocked nested defun"

# ─── Test 2: top-level defun (should be allowed) ───
echo "[test 2/2] pre-commit hook should allow top-level defun"
cat > lisp/modules/top-level-test.el << 'TOP_EOF'
;;; top-level-test.el --- Properly nested defun -*- lexical-binding: t; -*-

(defun gptel-auto-experiment--good-function ()
  "Properly top-level defun — parens are correct."
  42)

(provide 'top-level-test)
;;; top-level-test.el ends here
TOP_EOF

# Unstage the first file (which was rejected but still staged)
git reset HEAD lisp/modules/nested-test.el 2>/dev/null || true
rm -f lisp/modules/nested-test.el 2>/dev/null || true
git add lisp/modules/top-level-test.el
if ! $COMMIT -m "test top-level defun" >commit2.log 2>&1; then
    echo "FAIL: pre-commit hook blocked a clean top-level defun"
    cat commit2.log
    exit 1
fi
echo "PASS: pre-commit hook correctly allowed top-level defun"

echo "ALL TESTS PASSED"
