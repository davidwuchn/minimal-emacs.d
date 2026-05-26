#!/usr/bin/env bash
# TDD: verify daemon lifecycle management (kill, socket cleanup, PID tracking)

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
red='\033[0;31m'; green='\033[0;32m'; nc='\033[0m'
pass() { echo -e "${green}✓${nc} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${red}✗${nc} $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "=== $1 ==="; }

PIPELINE="$DIR/scripts/run-pipeline.sh"

section "pgrep patterns match daemon name across newline"

# Simulate daemon processes with names after newline (like macOS --bg-daemon)
# by using exec -a to set a process name containing ov5-
bash -c 'exec -a "ov5-auto-workflow" sleep 30' &
D1=$!
bash -c 'exec -a "ov5-researcher" sleep 30' &
D2=$!
sleep 0.3

# Test 1: pgrep finds both by name suffix
MATCHES=$(pgrep -f "ov5-auto-workflow" 2>/dev/null || true)
if [ -n "$MATCHES" ]; then
  pass "pgrep finds ov5-auto-workflow by name"
else
  fail "pgrep misses ov5-auto-workflow"
fi

MATCHES=$(pgrep -f "ov5-researcher" 2>/dev/null || true)
if [ -n "$MATCHES" ]; then
  pass "pgrep finds ov5-researcher by name"
else
  fail "pgrep misses ov5-researcher"
fi

# Test 2: pgrep finds both with combined pattern
MATCHES=$(pgrep -f "ov5-(auto-workflow|researcher)" 2>/dev/null || true)
MATCH_COUNT=$(echo "$MATCHES" | wc -l | tr -d ' ')
if [ "$MATCH_COUNT" -ge 2 ]; then
  pass "Combined pgrep pattern finds both daemons (count=$MATCH_COUNT)"
else
  fail "Combined pgrep pattern found only $MATCH_COUNT"
fi

# Kill test processes
kill $D1 $D2 2>/dev/null || true

# Test 3: Script syntax
if bash -n "$PIPELINE" 2>/dev/null; then
  pass "run-pipeline.sh syntax OK"
else
  fail "run-pipeline.sh syntax error"
fi

# Test 4: Verify pipeline has PID-based kill helper
if grep -q "kill_ov5_daemons\|pgrep -f \"ov5-" "$PIPELINE" 2>/dev/null; then
  pass "Pipeline uses pgrep-based daemon kill"
else
  fail "Pipeline missing pgrep-based daemon kill"
fi

section "Socket state after daemon death"

# Test 5: Clean stale socket function works
TMPDIR_SOCK=$(mktemp -d)
export TMPDIR="$TMPDIR_SOCK"
mkdir -p "$TMPDIR/emacs501"
python3 -c "
import socket, os
s = socket.socket(socket.AF_UNIX)
s.bind('$TMPDIR/emacs501/test-daemon')
os.chmod('$TMPDIR/emacs501/test-daemon', 0o600)
s.listen(1)
" &
SOCK_PID=$!
sleep 0.3

# Simulate what the pipeline does: kill daemon, then clean socket
kill $SOCK_PID 2>/dev/null || true
sleep 0.3

# Now the socket should still exist (orphaned) — verify the cleanup would remove it
resolve_live_socket() {
    local name="$1" uid="$2" sock=""
    for base in "${TMPDIR:-}" /tmp; do
        [ -n "$base" ] || continue
        sock="$base/emacs$uid/$name"
        if [ -S "$sock" ]; then
            return 0
        fi
    done
    return 1
}

resolve_live_socket "test-daemon" "501" 2>/dev/null
if [ $? -eq 0 ]; then
  pass "resolve_live_socket finds orphaned socket after daemon death"
else
  fail "resolve_live_socket should find orphaned socket"
fi

rm -rf "$TMPDIR_SOCK"

echo
echo "=== Summary: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
