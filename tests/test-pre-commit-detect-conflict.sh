#!/usr/bin/env bash
# TDD test for pre-commit merge-conflict detection hook.
# Run with: bash tests/test-pre-commit-detect-conflict.sh

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

# Set env vars so hook skips submodule sync / byte-compile in temp repo
export VERIFY_NUCLEUS_SKIP_SUBMODULE_SYNC=1

COMMIT="git -c core.hooksPath=.git/hooks commit"

# Helper: repeat a char 7 times (for conflict markers)
repeat7() { printf "$1%.0s" {1..7}; }

echo "[test 1/3] pre-commit hook should block files with conflict markers"
{
  echo "Some content before"
  echo "$(repeat7 '<') Updated upstream"
  echo "old line"
  echo "$(repeat7 '=')"
  echo "new line"
  echo "$(repeat7 '>') Stashed changes"
  echo "Some content after"
} > conflict-file.txt

git add conflict-file.txt
if $COMMIT -m "test conflict commit" >commit.log 2>&1; then
    echo "FAIL: pre-commit hook allowed commit of merge-conflict file"
    cat commit.log
    exit 1
fi

if ! grep -qi "merge conflict" commit.log; then
    echo "FAIL: hook did not report merge-conflict error (got: $(cat commit.log))"
    exit 1
fi

echo "PASS: pre-commit hook correctly blocked merge-conflict file"

# Reset staging so conflict file is not included in subsequent commit
git rm --cached -f conflict-file.txt >/dev/null 2>&1 || true
rm -f conflict-file.txt

echo "[test 2/3] pre-commit hook should allow clean files"
cat > clean-file.txt <<'EOF'
This file has no conflict markers.
EOF

git add clean-file.txt
if ! $COMMIT -m "test clean commit" >clean.log 2>&1; then
    echo "FAIL: pre-commit hook blocked a clean file"
    cat clean.log
    exit 1
fi

echo "PASS: pre-commit hook correctly allowed clean file"

echo "[test 3/3] pre-commit hook should block any file with markers (not just .el)"
{
  echo "# Doc"
  echo "Some text"
  echo "$(repeat7 '<') HEAD"
  echo "section A"
  echo "$(repeat7 '=')"
  echo "section B"
  echo "$(repeat7 '>') branch"
} > markdown.md

git add markdown.md
if $COMMIT -m "test markdown conflict commit" >md.log 2>&1; then
    echo "FAIL: pre-commit hook allowed commit of markdown conflict file"
    exit 1
fi

echo "PASS: pre-commit hook correctly blocked markdown conflict file"

echo ""
echo "All pre-commit hook tests passed."
