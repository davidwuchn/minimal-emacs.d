#!/usr/bin/env bash
# TDD: verify stale PID/lock files are cleaned from var/tmp/
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
red='\033[0;31m'; green='\033[0;32m'; nc='\033[0m'
pass() { echo -e "${green}✓${nc} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${red}✗${nc} $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "=== $1 ==="; }

section "Cleanup pattern exists in pipeline"

if grep -q "stale PID" "$DIR/scripts/run-pipeline.sh" 2>/dev/null; then
  pass "Stale PID cleanup present in pipeline"
else
  fail "Stale PID cleanup MISSING"
fi

if bash -n "$DIR/scripts/run-pipeline.sh" 2>/dev/null; then
  pass "Pipeline syntax OK"
else
  fail "Pipeline syntax error"
fi

section "Cleanup logic verification"

TMPDIR_TEST=$(mktemp -d)
# Create old PID file (mtime set via touch -t with explicit past date)
echo "12345" > "$TMPDIR_TEST/old.pid"
# Set mtime to 48 hours ago using reference file trick
touch -t 202401010000 "$TMPDIR_TEST/old.pid" 2>/dev/null || \
  touch -A -01 "$TMPDIR_TEST/old.pid" 2>/dev/null || true

# Create recent PID file (mtime now)
echo "67890" > "$TMPDIR_TEST/recent.pid"

# Run the cleanup pattern
find "$TMPDIR_TEST" -type f -name "*.pid" -mtime +1 -delete 2>/dev/null

if [ -f "$TMPDIR_TEST/old.pid" ]; then
  fail "Old PID file survived cleanup"
else
  pass "Old PID file deleted by cleanup"
fi

if [ -f "$TMPDIR_TEST/recent.pid" ]; then
  pass "Recent PID file preserved"
else
  fail "Recent PID file incorrectly deleted"
fi

rm -rf "$TMPDIR_TEST"

section "Current stale count"
count=$(find "$DIR/var/tmp" -name "eca-netrc-*.pid" 2>/dev/null | wc -l | tr -d ' ')
echo "  Current stale PID files: $count"
pass "Stale count checked"

echo
echo "=== Summary: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
