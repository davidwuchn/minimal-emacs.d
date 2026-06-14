#!/usr/bin/env bash
# TDD: 24/7 readiness checks
# Verifies all components needed for continuous operation

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
red='\033[0;31m'; green='\033[0;32m'; nc='\033[0m'
pass() { echo -e "${green}✓${nc} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${red}✗${nc} $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "=== $1 ==="; }

section "1. Cron Environment"

# Test that all cron PATH entries exist
for bin in emacsclient pgrep timeout bash; do
    path=$(/usr/bin/which "$bin" 2>/dev/null || true)
    if [ -n "$path" ]; then
        pass "Binary found in default PATH: $bin → $path"
    else
        fail "Binary not found: $bin"
    fi
done

# Test cron PATH resolution with the exact crontab PATH
CRON_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:$HOME/.emacs.d/bin"
for bin in emacsclient emacs pgrep timeout bash; do
    if env -i PATH="$CRON_PATH" which "$bin" >/dev/null 2>&1; then
        pass "Binary found in cron PATH: $bin"
    else
        fail "Binary missing from cron PATH: $bin"
    fi
done

section "2. Script Syntax"

for script in watchdog-daemon.sh run-pipeline.sh run-auto-workflow-cron.sh; do
    if bash -n "$DIR/scripts/$script" 2>/dev/null; then
        pass "Syntax OK: $script"
    else
        fail "Syntax error: $script"
    fi
done

section "3. State Persistence"

# cross-subsystem-state.edn must exist and be non-empty
state_file="$DIR/var/tmp/cross-subsystem-state.edn"
if [ -f "$state_file" ] && [ -s "$state_file" ]; then
    pass "cross-subsystem-state.edn exists ($(wc -c < "$state_file") bytes)"
else
    fail "cross-subsystem-state.edn missing or empty — next cycle starts with amnesia"
fi

# researcher-controller.edn must exist and be non-empty
controller_file="$DIR/var/tmp/researcher-controller.edn"
if [ -f "$controller_file" ] && [ -s "$controller_file" ]; then
    pass "researcher-controller.edn exists ($(wc -c < "$controller_file") bytes)"
else
    fail "researcher-controller.edn missing or empty — controller starts from defaults"
fi

section "3. Socket Directory Pinning"

# The workflow daemon pins server-socket-dir to /tmp/emacs$UID/.
# Scripts that invoke emacsclient must use /tmp as TMPDIR so socket discovery
# does not drift to /var/folders/.../T/ on macOS.
if grep -q 'export TMPDIR=/tmp' "$DIR/scripts/run-pipeline.sh"; then
    pass "run-pipeline.sh pins TMPDIR=/tmp for emacsclient"
else
    fail "run-pipeline.sh missing TMPDIR=/tmp pin — emacsclient socket drift likely"
fi
if grep -q 'export TMPDIR=${TMPDIR:-/tmp}' "$DIR/scripts/run-auto-workflow-cron.sh"; then
    pass "run-auto-workflow-cron.sh pins TMPDIR for emacsclient"
else
    fail "run-auto-workflow-cron.sh missing TMPDIR pin"
fi

section "4. Launchd Service"

if launchctl print gui/$(id -u)/org.gnu.emacs.daemon 2>&1 | grep -q "state = running"; then
    pass "Launchd Emacs daemon is running"
else
    fail "Launchd Emacs daemon is NOT running"
fi

section "5. Cron Schedule"

crontab -l 2>/dev/null > /tmp/test-crontab
if grep -q "watchdog-daemon.sh" /tmp/test-crontab; then
    pass "Watchdog cron job installed"
else
    fail "Watchdog cron job missing"
fi
if grep -q "run-pipeline.sh" /tmp/test-crontab; then
    pass "Pipeline cron job installed"
else
    fail "Pipeline cron job missing"
fi
rm -f /tmp/test-crontab

section "6. Disk Space"

tmp_usage=$(du -sk "$DIR/var/tmp" 2>/dev/null | awk '{print $1}')
if [ "$tmp_usage" -lt 102400 ]; then
    pass "Disk usage OK: ${tmp_usage}KB (< 100MB)"
else
    fail "High disk usage: ${tmp_usage}KB"
fi

section "7. Daemon Kill Logic"

# Test that kill_ov5_daemons pattern exists in pipeline
if grep -q "kill_ov5_daemons" "$DIR/scripts/run-pipeline.sh"; then
    pass "PID-based daemon kill function present"
else
    fail "PID-based daemon kill function MISSING"
fi

# Test pgrep can find ov5 daemon names
bash -c 'exec -a "ov5-probe-test" sleep 5' &
P=$!
sleep 0.2
MATCHES=$(pgrep -f "ov5-probe-test" 2>/dev/null || true)
kill $P 2>/dev/null || true
if [ -n "$MATCHES" ]; then
    pass "pgrep matches ov5 daemon names across newlines"
else
    fail "pgrep fails to match ov5 daemon names — 24/7 daemon kill broken"
fi

section "8. Daemon zero-leak check (no orphaned processes)"

orphans=$(pgrep -f "ov5-(auto-workflow|researcher)" 2>/dev/null || true)
if [ -z "$orphans" ]; then
    pass "No orphaned ov5 daemon processes"
else
    count=$(echo "$orphans" | wc -l | tr -d ' ')
    warn "Found $count orphaned ov5 daemon(s): $(echo "$orphans" | tr '\n' ' ')"
fi

echo
echo "=== Summary: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
