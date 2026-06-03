#!/usr/bin/env bash
# TDD: verify install-cron.sh outputs valid XDG_RUNTIME_DIR with numeric UID
# Regression: literal '$(id -u)' in crontab caused "Permission denied" daemon start

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
red='\033[0;31m'; green='\033[0;32m'; nc='\033[0m'
pass() { echo -e "${green}✓${nc} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${red}✗${nc} $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "=== $1 ==="; }

INSTALL_CRON="$DIR/scripts/install-cron.sh"

section "install-cron.sh outputs numeric UID in XDG_RUNTIME_DIR"

# Generate crontab output for linux machine
# The script uses --render mode and detects machine automatically
# We force linux by setting a fake hostname, or we can just check the output
CRONTAB_OUTPUT="$(MACHINE_RENDER=linux bash "$INSTALL_CRON" --render 2>/dev/null || true)"

# Extract XDG_RUNTIME_DIR line
XDG_LINE="$(printf '%s\n' "$CRONTAB_OUTPUT" | grep '^XDG_RUNTIME_DIR=' || true)"

if [ -z "$XDG_LINE" ]; then
  fail "No XDG_RUNTIME_DIR line found in crontab output"
else
  pass "XDG_RUNTIME_DIR line found: $XDG_LINE"
  
  # Verify it contains an actual number, not literal $(id -u)
  if printf '%s\n' "$XDG_LINE" | grep -q '\$(id -u)'; then
    fail "XDG_RUNTIME_DIR contains literal '\$(id -u)' — must be numeric UID"
  else
    pass "XDG_RUNTIME_DIR does not contain literal '\$(id -u)'"
  fi
  
  # Verify the path ends with a number
  UID_PART="${XDG_LINE##*/}"
  if printf '%s\n' "$UID_PART" | grep -Eq '^[0-9]+$'; then
    pass "XDG_RUNTIME_DIR ends with numeric UID: $UID_PART"
  else
    fail "XDG_RUNTIME_DIR does not end with numeric UID: $UID_PART"
  fi
fi

section "install-cron.sh does not escape \$(id -u) in output"

# Check the script source for the bug
if grep -q '\\\$(id -u)' "$INSTALL_CRON"; then
  fail "install-cron.sh still contains escaped '\\\$(id -u)'"
else
  pass "install-cron.sh does not contain escaped '\\\$(id -u)'"
fi

# Summary
echo
if [ "$FAIL" -eq 0 ]; then
  echo -e "${green}All tests passed${nc} ($PASS assertions)"
  exit 0
else
  echo -e "${red}Tests failed${nc}: $FAIL failed, $PASS passed"
  exit 1
fi
