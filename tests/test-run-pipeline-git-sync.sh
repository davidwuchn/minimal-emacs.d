#!/usr/bin/env bash
# TDD: run-pipeline git sync must not replay stale stashes on unmerged paths.
# Rewritten to exercise new Clojure git helpers via `bb -e`.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
red='\033[0;31m'
green='\033[0;32m'
nc='\033[0m'

pass() { echo -e "${green}✓${nc} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${red}✗${nc} $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "=== $1 ==="; }

section "Clojure git helpers: function presence"

if bb --config "$DIR/bb.edn" --deps-root "$DIR" -e "(require 'ov5.pipeline.git) (println (mapv #(contains? (ns-publics 'ov5.pipeline.git) %) '[has-unmerged-paths? clear-auto-generated-unmerged-paths! git-sync-latest! fetch-and-rebase!]))" 2>/dev/null | grep -q "true"; then
  pass "ov5.pipeline.git namespace loads and exports key functions"
else
  fail "ov5.pipeline.git namespace missing key functions"
fi

section "Auto-generated conflict detection"
# Create a temp git repo to test unmerged-path detection
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

cd "$TEST_DIR"
git init -q
git checkout -b main -q 2>/dev/null || git branch -m main 2>/dev/null || true
git config user.email "test@example.com"
git config user.name "Test"
git commit --allow-empty -m "initial" -q

# Create an auto-gen file and produce a merge conflict
mkdir -p mementum/knowledge
echo "upstream content" > mementum/knowledge/backend-comparison.md
git add mementum/knowledge/backend-comparison.md
git commit -m "add auto-gen file" -q

git checkout -b side -q
echo "side content" > mementum/knowledge/backend-comparison.md
git add mementum/knowledge/backend-comparison.md
git commit -m "side change" -q

git checkout main -q
echo "main content" > mementum/knowledge/backend-comparison.md
git add mementum/knowledge/backend-comparison.md
git commit -m "main change" -q

# Trigger a merge conflict
git merge side 2>/dev/null || true

if bb --config "$DIR/bb.edn" --deps-root "$DIR" -e "(require 'ov5.pipeline.git) (println (ov5.pipeline.git/has-unmerged-paths? \"$TEST_DIR\"))" 2>/dev/null | grep -q "true"; then
  pass "has-unmerged-paths? detects conflicts in auto-gen dirs"
else
  fail "has-unmerged-paths? failed to detect merge conflict"
fi

section "Auto-generated conflict cleanup"
if bb --config "$DIR/bb.edn" --deps-root "$DIR" -e "(require 'ov5.pipeline.git) (println (ov5.pipeline.git/clear-auto-generated-unmerged-paths! \"$TEST_DIR\"))" 2>/dev/null | grep -q "true"; then
  pass "auto-generated unmerged paths are clearable"
else
  fail "auto-generated unmerged paths should be clearable"
fi

# Verify no unmerged paths remain
if git diff --name-only --diff-filter=U 2>/dev/null | grep -q .; then
  fail "unmerged paths remain after cleanup"
else
  pass "no unmerged paths remain after cleanup"
fi

cd "$DIR"

section "Non-auto-gen conflict blocks cleanup"
TEST_DIR2="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR" "$TEST_DIR2"' EXIT

cd "$TEST_DIR2"
git init -q
git checkout -b main -q 2>/dev/null || git branch -m main 2>/dev/null || true
git config user.email "test@example.com"
git config user.name "Test"
git commit --allow-empty -m "initial" -q

# Create a non-auto-gen conflict
mkdir -p src
echo "content" > src/core.clj
git add src/core.clj
git commit -m "add non-auto-gen" -q

git checkout -b side2 -q
echo "side content" > src/core.clj
git add src/core.clj
git commit -m "side non-auto-gen change" -q

git checkout main -q
echo "main content" > src/core.clj
git add src/core.clj
git commit -m "main non-auto-gen change" -q

git merge side2 2>/dev/null || true

if bb --config "$DIR/bb.edn" --deps-root "$DIR" -e "(require 'ov5.pipeline.git) (println (ov5.pipeline.git/clear-auto-generated-unmerged-paths! \"$TEST_DIR2\"))" 2>/dev/null | grep -q "false"; then
  pass "non-auto-gen unmerged paths block cleanup (returns false)"
else
  fail "non-auto-gen unmerged paths should block cleanup"
fi

cd "$DIR"

section "Wrapper syntax"
if bash -n "$DIR/scripts/run-pipeline.sh" 2>/dev/null; then
  pass "run-pipeline.sh syntax OK"
else
  fail "run-pipeline.sh syntax error"
fi

echo
echo "=== Summary: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
