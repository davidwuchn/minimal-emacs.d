#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRON_FILE="$DIR/cron.d/auto-workflow"
RUNNER="$DIR/scripts/run-auto-workflow-cron.sh"
INSTALLER="$DIR/scripts/install-cron.sh"
LOGDIR="$DIR/var/tmp/cron"
FULL_TEST="${1:-}"

RED='[0;31m'
GREEN='[0;32m'
YELLOW='[1;33m'
NC='[0m'

PASS=0
FAIL=0
SKIP=0

pass() { echo -e "${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }
skip() { echo -e "${YELLOW}○${NC} $1"; SKIP=$((SKIP + 1)); }
section() { echo; echo "=== $1 ==="; }

run_batch_bootstrap() {
    emacs --batch -Q \
        -L "$DIR" \
        -L "$DIR/lisp" \
        -L "$DIR/lisp/modules" \
        -L "$DIR/packages/gptel" \
        -L "$DIR/packages/gptel-agent" \
        -l "$DIR/scripts/test-auto-workflow-batch.el" \
        -f test-auto-workflow-batch-run
}

section "Cron Template"
if [ -f "$CRON_FILE" ]; then
    pass "Crontab template exists: $CRON_FILE"
else
    fail "Crontab template missing: $CRON_FILE"
    exit 1
fi

if grep -q 'SHELL=/bin/bash' "$CRON_FILE"; then
    pass "SHELL=/bin/bash is set"
else
    fail "SHELL not set to /bin/bash"
fi

if grep -q 'run-auto-workflow-cron.sh auto-workflow' "$CRON_FILE"; then
    pass "Template uses wrapper for auto-workflow"
else
    fail "Template does not use wrapper for auto-workflow"
fi

RENDERED=$(mktemp)
"$INSTALLER" --render > "$RENDERED"

section "Rendered Crontab"
if grep -Eq '^[0-9*@]' "$RENDERED"; then
    pass "Rendered crontab contains active schedules"
    grep -E '^[0-9*@]' "$RENDERED" | sed 's/^/    /'
else
    fail "Rendered crontab has no active schedules"
fi

if crontab -l >/dev/null 2>&1; then
    pass "User crontab is installed"
    if diff -u "$RENDERED" <(crontab -l) >/dev/null 2>&1; then
        pass "Installed crontab matches rendered output"
    else
        fail "Installed crontab differs from rendered output"
        echo "    Run: ./scripts/install-cron.sh"
    fi
else
    skip "No user crontab installed"
fi

section "Required Directories"
if [ -d "$LOGDIR" ]; then
    pass "Log directory exists: $LOGDIR"
else
    fail "Log directory missing: $LOGDIR"
fi

if [ -d "$DIR/var/tmp/experiments" ]; then
    pass "Experiments directory exists"
else
    skip "Experiments directory missing (will be created on first run)"
fi

section "Cron Daemon"
if systemctl is-active --quiet cron 2>/dev/null; then
    pass "Cron daemon is running (systemd)"
elif service cron status >/dev/null 2>&1; then
    pass "Cron daemon is running (service)"
elif pgrep -x "cron" >/dev/null; then
    pass "Cron daemon is running (pgrep)"
else
    fail "Cron daemon is NOT running"
fi

section "Emacs Access"
if [ -x "$RUNNER" ]; then
    pass "Wrapper exists: $RUNNER"
else
    fail "Wrapper missing or not executable: $RUNNER"
fi

if "$RUNNER" status | grep -q ':phase'; then
    pass "Wrapper returns a workflow status snapshot"
else
    fail "Wrapper status failed"
fi

section "Cron Functions"
if run_batch_bootstrap >/dev/null 2>&1; then
    pass "Workflow modules and cron entrypoints load in batch mode"
else
    fail "Workflow modules or cron entrypoints failed to load in batch mode"
fi

section "Log File Writability"
TEST_LOG="$LOGDIR/test-write-$$.log"
if touch "$TEST_LOG" 2>/dev/null; then
    pass "Can create log files in $LOGDIR"
    rm -f "$TEST_LOG"
else
    fail "Cannot create log files in $LOGDIR"
fi

section "Recent Execution"
check_log() {
    local logname="$1"
    local logfile="$LOGDIR/$logname"

    if [ -f "$logfile" ]; then
        local size mtime now age
        size=$(stat -c%s "$logfile" 2>/dev/null || stat -f%z "$logfile" 2>/dev/null)
        mtime=$(stat -c%Y "$logfile" 2>/dev/null || stat -f%m "$logfile" 2>/dev/null)
        now=$(date +%s)
        age=$((now - mtime))
        if [ "$size" -gt 0 ]; then
            if [ "$age" -lt 86400 ]; then
                pass "$logname: ${size} bytes, modified $((age / 3600))h $(((age % 3600) / 60))m ago"
            else
                pass "$logname: ${size} bytes, modified $((age / 86400)) days ago"
            fi
        else
            pass "$logname: exists but empty"
        fi
    else
        skip "$logname: not found (job may not have run yet)"
    fi
}

check_log auto-workflow.log
check_log researcher.log
check_log mementum.log
check_log instincts.log

if [ "$FULL_TEST" = "--full" ]; then
    section "Full Function Test"
    if "$RUNNER" status | grep -q ':phase'; then
        pass "Wrapper status executed successfully"
    else
        fail "Wrapper status failed"
    fi
else
    section "Full Function Test"
    skip "Use --full to run the wrapper status check explicitly"
fi

rm -f "$RENDERED"

echo
echo "═══════════════════════════════════════════════════════════════"
echo -e "Summary: ${GREEN}PASS: $PASS${NC} ${RED}FAIL: $FAIL${NC} ${YELLOW}SKIP: $SKIP${NC}"
echo "═══════════════════════════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
    echo
    echo "Fix failures before cron jobs will work correctly."
    exit 1
fi

exit 0
