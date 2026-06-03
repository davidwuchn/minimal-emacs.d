#!/usr/bin/env bash
# TDD: verify installed crontab has numeric UID in XDG_RUNTIME_DIR
# Regression: literal '$(id -u)' caused daemon "Permission denied"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
red='\033[0;31m'; green='\033[0;32m'; nc='\033[0m'
pass() { echo -e "${green}✓${nc} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${red}✗${nc} $1"; FAIL=$((FAIL + 1)); }

# Check installed crontab
XDG_LINE="$(crontab -l 2>/dev/null | grep '^XDG_RUNTIME_DIR=' || true)"

if [ -z "$XDG_LINE" ]; then
  fail "No XDG_RUNTIME_DIR in crontab"
else
  pass "XDG_RUNTIME_DIR found: $XDG_LINE"
  
  if echo "$XDG_LINE" | grep -q '\$(id -u)'; then
    fail "Contains literal '\$(id -u)' — daemon will fail"
  else
    pass "No literal '\$(id -u)'"
  fi
  
  UID_PART="${XDG_LINE##*/}"
  if echo "$UID_PART" | grep -Eq '^[0-9]+$'; then
    pass "Ends with numeric UID: $UID_PART"
  else
    fail "Does not end with numeric UID: $UID_PART"
  fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo -e "${green}All tests passed${nc} ($PASS assertions)"
  exit 0
else
  echo -e "${red}Tests failed${nc}: $FAIL failed, $PASS passed"
  exit 1
fi
