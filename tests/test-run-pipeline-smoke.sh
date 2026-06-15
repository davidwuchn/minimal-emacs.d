#!/usr/bin/env bash
# Smoke test for run-pipeline.sh wrapper and bb -m ov5.pipeline entry point.
# Validates: wrapper exists, executable, bash syntax OK, --help works, and
# --smoke runs without crashing in an isolated temp project root.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$DIR/scripts/run-pipeline.sh"
PASS=0
FAIL=0
red='\033[0;31m'
green='\033[0;32m'
nc='\033[0m'

pass() { echo -e "${green}✓${nc} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${red}✗${nc} $1"; FAIL=$((FAIL + 1)); }

section() { echo; echo "=== $1 ==="; }

cleanup_dirs=()

cleanup() {
  for d in "${cleanup_dirs[@]}"; do
    rm -rf "$d" 2>/dev/null || true
  done
}
trap cleanup EXIT

section "Wrapper script existence"

if [ -f "$WRAPPER" ]; then
  pass "wrapper script exists: scripts/run-pipeline.sh"
else
  fail "wrapper script missing: scripts/run-pipeline.sh"
  echo "=== Summary: $PASS passed, $FAIL failed ==="
  [ "$FAIL" -eq 0 ] || exit 1
fi

if [ -x "$WRAPPER" ]; then
  pass "wrapper script is executable"
else
  fail "wrapper script is not executable"
fi

section "Wrapper bash syntax"

if bash -n "$WRAPPER" 2>/dev/null; then
  pass "wrapper passes bash -n syntax check"
else
  fail "wrapper has bash syntax errors"
fi

section "bb -m ov5.pipeline --help"

if bb --deps-root "$DIR" -m ov5.pipeline --help 2>&1 | grep -qiE "Usage|pipeline" ; then
  pass "bb -m ov5.pipeline --help prints usage"
elif bb --deps-root "$DIR" -m ov5.pipeline --help >/dev/null 2>&1; then
  pass "bb -m ov5.pipeline --help exits 0"
else
  fail "bb -m ov5.pipeline --help failed"
fi

section "Wrapper resolves project root"

# Accept either a bare `bb` or a resolved "$BB_BIN" (cron PATH may lack mise shims).
if grep -qE 'exec "?(\$BB_BIN|bb)"? -m ov5\.pipeline' "$WRAPPER"; then
  pass "wrapper delegates to bb -m ov5.pipeline"
else
  fail "wrapper does not delegate to bb -m ov5.pipeline"
fi

if grep -q 'export TMPDIR=/tmp' "$WRAPPER"; then
  pass "wrapper pins TMPDIR=/tmp"
else
  fail "wrapper does not pin TMPDIR=/tmp"
fi

section "--dry-run runs in isolated project root"

TMP_DIR="$(mktemp -d /tmp/ov5-pipeline-smoke-XXXXXX)"
cleanup_dirs+=("$TMP_DIR")

# Create minimal project skeleton so the pipeline can set up environment without
# touching the real repo.
mkdir -p "$TMP_DIR/var/tmp/cron"
mkdir -p "$TMP_DIR/var/tmp/experiments"
mkdir -p "$TMP_DIR/mementum/memories"
mkdir -p "$TMP_DIR/mementum/knowledge"
mkdir -p "$TMP_DIR/assistant/skills"
mkdir -p "$TMP_DIR/assistant/strategies"
cat > "$TMP_DIR/mementum/state.md" <<EOF
# Mementum State

> **Status**: smoke-test project
EOF

# Initialize a git repo so environment resolution doesn't crash.
git -C "$TMP_DIR" init -q
git -C "$TMP_DIR" config user.email "smoke@test"
git -C "$TMP_DIR" config user.name "Smoke Test"
git -C "$TMP_DIR" add .
git -C "$TMP_DIR" commit -q -m "initial"

# Capture real repo state.md checksum before running pipeline.
REAL_STATE="$DIR/mementum/state.md"
BEFORE_SUM=$(md5sum "$REAL_STATE" 2>/dev/null | awk '{print $1}' || md5 -q "$REAL_STATE" 2>/dev/null || echo "0")

set +e
PIPELINE_OUTPUT=$(PIPELINE_PROJECT_ROOT="$TMP_DIR" bb --deps-root "$DIR" -m ov5.pipeline --dry-run 2>&1)
PIPELINE_EXIT=$?
set -e

if [ "$PIPELINE_EXIT" -eq 0 ]; then
  pass "bb -m ov5.pipeline --dry-run exits 0 in isolated project root"
else
  fail "bb -m ov5.pipeline --dry-run failed (exit=$PIPELINE_EXIT)"
fi

if echo "$PIPELINE_OUTPUT" | grep -qiE "FileNotFoundException|class not found|ExceptionInInitializerError"; then
  fail "bb -m ov5.pipeline --dry-run crashed with class/pod error"
else
  pass "bb -m ov5.pipeline --dry-run executed without class/pod crash"
fi

# Verify the real repo's mementum/state.md was not touched.
AFTER_SUM=$(md5sum "$REAL_STATE" 2>/dev/null | awk '{print $1}' || md5 -q "$REAL_STATE" 2>/dev/null || echo "1")
if [ "$BEFORE_SUM" = "$AFTER_SUM" ]; then
  pass "real mementum/state.md unchanged by dry-run"
else
  fail "real mementum/state.md was modified by dry-run"
fi

echo
echo "=== Summary: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
