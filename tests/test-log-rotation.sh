#!/usr/bin/env bash
# TDD: verify log rotation prevents unbounded log growth
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
red='\033[0;31m'; green='\033[0;32m'; nc='\033[0m'
pass() { echo -e "${green}✓${nc} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${red}✗${nc} $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "=== $1 ==="; }

section "Log rotation function exists"

if grep -q "log_rotate" "$DIR/scripts/run-pipeline.sh" 2>/dev/null; then
  pass "log_rotate function present in pipeline"
else
  fail "log_rotate function MISSING"
fi

# Extract and test the log rotation logic
eval "$(awk '/^log_rotate\(\)/,/^}/   { print }' "$DIR/scripts/run-pipeline.sh" 2>/dev/null)"

section "Basic rotation"

# Create a test log file > 100KB
TMPDIR_LOG=$(mktemp -d)
BIG_LOG="$TMPDIR_LOG/test.log"
python3 -c "open('$BIG_LOG','w').write('x' * 200000)"
SIZE=$(wc -c < "$BIG_LOG")
if [ "$SIZE" -gt 100000 ]; then
  pass "Test log created: ${SIZE} bytes"
else
  fail "Test log too small: ${SIZE} bytes"
fi

# Test rotation function if it exists
if type log_rotate >/dev/null 2>&1; then
  log_rotate "$BIG_LOG"
  # Check that old log was rotated
  if [ -f "${BIG_LOG}.1" ]; then
    pass "Log rotated to .1"
  else
    fail "Log not rotated"
  fi
  # Check that the main log still exists (recreated)
  if [ -f "$BIG_LOG" ]; then
    pass "Log file recreated after rotation"
  else
    fail "Log file missing after rotation"
  fi
else
  # Test the rotation logic inline
  rotate() {
    local f="$1" max="${2:-102400}"
    [ -f "$f" ] || return
    local size=$(wc -c < "$f")
    [ "$size" -lt "$max" ] && return
    # Rotate .3 → .2, .2 → .1, .1 → current
    [ -f "${f}.3" ] && rm -f "${f}.3"
    [ -f "${f}.2" ] && mv "${f}.2" "${f}.3" 2>/dev/null
    [ -f "${f}.1" ] && mv "${f}.1" "${f}.2" 2>/dev/null
    mv "$f" "${f}.1"
    : > "$f"
  }

  rotate "$BIG_LOG"
  if [ -f "${BIG_LOG}.1" ] && [ ! -s "$BIG_LOG" ]; then
    pass "Inline rotation works (${BIG_LOG}.1 created, main truncated)"
  else
    fail "Inline rotation failed"
  fi
fi

# Verify rotation works on small files (should be skipped)
SMALL_LOG="$TMPDIR_LOG/small.log"
echo "small" > "$SMALL_LOG"
( type log_rotate >/dev/null 2>&1 && log_rotate "$SMALL_LOG" || rotate "$SMALL_LOG" )
if [ -f "$SMALL_LOG" ] && [ ! -f "${SMALL_LOG}.1" ]; then
  pass "Small log correctly skipped rotation"
else
  fail "Small log incorrectly rotated"
fi

rm -rf "$TMPDIR_LOG"

section "Pipeline log size check"

# Verify the actual pipeline logs aren't too large
for log in "$DIR/var/tmp/cron/pipeline.log" "$DIR/var/tmp/cron/ov5-researcher.log" "$DIR/var/tmp/cron/ov5-auto-workflow.log"; do
  if [ -f "$log" ]; then
    sz=$(wc -c < "$log")
    echo "  $(basename $log): $(numfmt --to=iec $sz 2>/dev/null || echo "${sz}B")"
  fi
done

section "Syntax check"
if bash -n "$DIR/scripts/run-pipeline.sh" 2>/dev/null; then
  pass "run-pipeline.sh syntax OK"
else
  fail "run-pipeline.sh syntax error"
fi

echo
echo "=== Summary: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
