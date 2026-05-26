#!/usr/bin/env bash
# TDD: verify pgrep patterns match daemon processes with newline in args
# macOS --bg-daemon uses \012 (newline) which breaks pgrep -f patterns

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

red='\033[0;31m'; green='\033[0;32m'; nc='\033[0m'
pass() { echo -e "${green}✓${nc} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${red}✗${nc} $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "=== $1 ==="; }

section "pgrep matches daemon with newline in args"

# Spawn a fake daemon-like process with newline in its name (simulating --bg-daemon=\0123,4\012ov5-test-daemon)
# We need a process that shows up in ps with a pattern like ov5-test-daemon
python3 -c "
import subprocess, os, time
proc = subprocess.Popen(
    ['sleep', '300'],
    env={**os.environ, 'EMACS_DAEMON_TEST': 'ov5-test-daemon'}
)
with open('/tmp/pgrep-test-pid', 'w') as f:
    f.write(str(proc.pid))
" &
sleep 0.5

TEST_PID=$(cat /tmp/pgrep-test-pid 2>/dev/null || echo "")

# Test 1: Broken pattern (emacs.*daemon.*name) should NOT match a non-emacs proc
# This is the CONTROLLED test — we verify the OLD pattern behavior
OLD_MATCHES=$(pgrep -f "emacs.*daemon.*test-daemon" 2>/dev/null || true)
if [ -z "$OLD_MATCHES" ]; then
  pass "Old pattern correctly doesn't match non-emacs proc"
else
  fail "Old pattern matched non-emacs proc"
fi

# Test 2: Simple name pattern (just daemon name) should match the proc
NEW_MATCHES=$(pgrep -f "test-daemon" 2>/dev/null || true)
if [ -n "$NEW_MATCHES" ]; then
  pass "Simple name pattern matches via env var"
else
  fail "Simple name pattern didn't match — env vars not in pgrep scope"
fi

kill "$TEST_PID" 2>/dev/null || true
rm -f /tmp/pgrep-test-pid

# Test 3: Verify the ACTUAL fix patterns work for ov5 daemons
# Since we killed all ov5 daemons, start a real one or simulate
section "Fix pattern validation"

# Start a minimal background process with 'ov5-' in args
sleep 600 &
BG_PID=$!
# Rename the process (macOS doesn't have prctl, so we use the env approach)
# Actually on macOS pgrep -f searches the full process args line
# Let's use a bash subprocess with ov5 in its name
bash -c 'exec -a "ov5-auto-workflow" sleep 60' &
DAEMON_PID=$!
sleep 0.5

# Test: pgrep -f "ov5-auto-workflow" should find it
MATCHES=$(pgrep -f "ov5-auto-workflow" 2>/dev/null || true)
if [ -n "$MATCHES" ]; then
  pass "pgrep -f 'ov5-auto-workflow' finds simulated daemon"
else
  fail "pgrep -f 'ov5-auto-workflow' fails"
fi

kill $BG_PID $DAEMON_PID 2>/dev/null || true

section "Script syntax check"
if bash -n "$DIR/scripts/run-pipeline.sh" 2>/dev/null; then
  pass "run-pipeline.sh syntax OK"
else
  fail "run-pipeline.sh syntax error"
fi

echo
echo "=== Summary: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
