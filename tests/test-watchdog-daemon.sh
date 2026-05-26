#!/usr/bin/env bash
# TDD tests for watchdog-daemon.sh functions
# Run: bash tests/test-watchdog-daemon.sh

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHDOG="$DIR/scripts/watchdog-daemon.sh"
PASS=0
FAIL=0

red='\033[0;31m'
green='\033[0;32m'
nc='\033[0m'

pass() { echo -e "${green}✓${nc} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${red}✗${nc} $1"; FAIL=$((FAIL + 1)); }

section() { echo; echo "=== $1 ==="; }

# Extract function bodies from watchdog to a temp file, then source it.
# Using sed to extract cleanly between function boundaries.
TMP_FUNCS=$(mktemp)
trap 'rm -f "$TMP_FUNCS"' EXIT

# Use line-number-based extraction for precision
resolve_start=$(grep -n '^resolve_live_socket()' "$WATCHDOG" | head -1 | cut -d: -f1)
resolve_end=$(tail -n +"$resolve_start" "$WATCHDOG" | grep -n '^}' | head -1 | cut -d: -f1)
resolve_end=$((resolve_start + resolve_end - 1))

clean_start=$(grep -n '^clean_all_sockets()' "$WATCHDOG" | head -1 | cut -d: -f1)
clean_end=$(tail -n +"$clean_start" "$WATCHDOG" | grep -n '^}' | head -1 | cut -d: -f1)
clean_end=$((clean_start + clean_end - 1))

proc_start=$(grep -n '^proc_is_running()' "$WATCHDOG" | head -1 | cut -d: -f1)
proc_end=$(tail -n +"$proc_start" "$WATCHDOG" | grep -n '^}' | head -1 | cut -d: -f1)
proc_end=$((proc_start + proc_end - 1))

sed -n "${resolve_start},${resolve_end}p" "$WATCHDOG" > "$TMP_FUNCS"
sed -n "${clean_start},${clean_end}p" "$WATCHDOG" >> "$TMP_FUNCS"
sed -n "${proc_start},${proc_end}p" "$WATCHDOG" >> "$TMP_FUNCS"

section "resolve_live_socket"

source "$TMP_FUNCS"

if type resolve_live_socket >/dev/null 2>&1; then
  pass "resolve_live_socket function defined"
else
  fail "resolve_live_socket function not defined"
fi

SOCKET_PATH=""
if resolve_live_socket "nonexistent" "99999" 2>/dev/null; then
  fail "resolve_live_socket should fail for non-existent socket (no TMPDIR)"
else
  pass "resolve_live_socket fails for non-existent socket (no TMPDIR)"
fi

TMPDIR_SOCK=$(mktemp -d)
export TMPDIR="$TMPDIR_SOCK"
mkdir -p "$TMPDIR/emacs501"
# Create a real Unix domain socket with a background listener
python3 -c "
import socket, os
s = socket.socket(socket.AF_UNIX)
s.bind('$TMPDIR/emacs501/test-sock')
os.chmod('$TMPDIR/emacs501/test-sock', 0o600)
s.listen(1)
print('ready')
" &
SOCK_PID=$!
sleep 0.3
SOCKET_PATH=""
if resolve_live_socket "test-sock" "501" 2>/dev/null; then
  pass "resolve_live_socket finds socket with TMPDIR"
  kill $SOCK_PID 2>/dev/null || true
else
  kill $SOCK_PID 2>/dev/null || true
  fail "resolve_live_socket should find socket with TMPDIR ($TMPDIR/emacs501/test-sock)"
fi
unset TMPDIR
rm -rf "$TMPDIR_SOCK"

section "clean_all_sockets"

source "$TMP_FUNCS"

TMPDIR_CLEAN=$(mktemp -d)
mkdir -p "$TMPDIR_CLEAN/emacs501"
python3 -c "
import socket, os
s = socket.socket(socket.AF_UNIX)
s.bind('$TMPDIR_CLEAN/emacs501/ov5-test')
os.chmod('$TMPDIR_CLEAN/emacs501/ov5-test', 0o600)
s.listen(1)
print('ready')
" &
SOCK_PID=$!
sleep 0.3
export TMPDIR="$TMPDIR_CLEAN"
clean_all_sockets "ov5-test" "501" 2>/dev/null || true
if [ -e "$TMPDIR_CLEAN/emacs501/ov5-test" ]; then
  fail "clean_all_sockets should remove socket file"
else
  pass "clean_all_sockets removes socket file"
fi
kill $SOCK_PID 2>/dev/null || true
unset TMPDIR
rm -rf "$TMPDIR_CLEAN"

section "proc_is_running"

source "$TMP_FUNCS"

if proc_is_running "" 2>/dev/null; then
  fail "proc_is_running should fail for empty PID"
else
  pass "proc_is_running fails for empty PID"
fi

if proc_is_running "$$" 2>/dev/null; then
  pass "proc_is_running succeeds for current PID"
else
  fail "proc_is_running should succeed for current PID"
fi

if proc_is_running "999999999" 2>/dev/null; then
  fail "proc_is_running should fail for non-existent PID"
else
  pass "proc_is_running fails for non-existent PID"
fi

section "Script syntax check"

if bash -n "$WATCHDOG" 2>/dev/null; then
  pass "watchdog-daemon.sh has valid bash syntax"
else
  fail "watchdog-daemon.sh has bash syntax errors"
fi

section "main flow - cooldown check"
# Test that the cooldown mechanism works: run without any daemon,
# it should not get stuck.

echo
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "SOME TESTS FAILED"
  exit 1
fi
echo "ALL TESTS PASSED"
exit 0
