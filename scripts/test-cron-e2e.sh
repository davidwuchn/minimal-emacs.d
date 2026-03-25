#!/usr/bin/env bash

# test-cron-e2e.sh
# End-to-end test for cron job configuration
#
# Tests:
# 1. Crontab file syntax and variable expansion
# 2. Required directories exist
# 3. Cron daemon is running
# 4. Emacs server is accessible
# 5. Cron functions are callable
# 6. Log files are writable
#
# Usage:
#   ./scripts/test-cron-e2e.sh [--full]

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRON_FILE="$DIR/cron.d/auto-workflow"
LOGDIR="$DIR/var/tmp/cron"
FULL_TEST="${1:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
SKIP=0

pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASS=$((PASS + 1))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    FAIL=$((FAIL + 1))
}

skip() {
    echo -e "${YELLOW}○${NC} $1"
    SKIP=$((SKIP + 1))
}

section() {
    echo ""
    echo "=== $1 ==="
}

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: Crontab File Syntax
# ═══════════════════════════════════════════════════════════════════════════

section "Crontab File Syntax"

if [ -f "$CRON_FILE" ]; then
    pass "Crontab file exists: $CRON_FILE"
else
    fail "Crontab file missing: $CRON_FILE"
    exit 1
fi

# Check LOGDIR uses $HOME not ~
if grep -q 'LOGDIR=\$HOME' "$CRON_FILE"; then
    pass "LOGDIR uses \$HOME (expands correctly in cron)"
elif grep -q 'LOGDIR=~' "$CRON_FILE"; then
    fail "LOGDIR uses ~ (will NOT expand in cron! Use \$HOME instead)"
else
    fail "LOGDIR variable not found in crontab"
fi

# Check SHELL is set
if grep -q 'SHELL=/bin/bash' "$CRON_FILE"; then
    pass "SHELL=/bin/bash is set"
else
    fail "SHELL not set to /bin/bash"
fi

# Check schedule syntax (basic validation)
SCHEDULES=$(grep -v '^#' "$CRON_FILE" | grep -v '^$' | grep -v '^SHELL' | grep -v '^LOGDIR' | grep -v '@reboot')
if [ -n "$SCHEDULES" ]; then
    pass "Cron schedules found"
    echo "$SCHEDULES" | while read -r line; do
        echo "    $line"
    done
else
    fail "No cron schedules found"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: Required Directories
# ═══════════════════════════════════════════════════════════════════════════

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

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: Cron Daemon
# ═══════════════════════════════════════════════════════════════════════════

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

# Check crontab is installed
if crontab -l >/dev/null 2>&1; then
    pass "User crontab is installed"
    
    # Check if our cron file matches installed crontab
    if diff -q <(crontab -l) "$CRON_FILE" >/dev/null 2>&1; then
        pass "Installed crontab matches cron.d/auto-workflow"
    else
        fail "Installed crontab differs from cron.d/auto-workflow"
        echo "    Run: crontab $CRON_FILE"
    fi
else
    skip "No user crontab installed"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: Emacs Server
# ═══════════════════════════════════════════════════════════════════════════

section "Emacs Server"

if command -v emacsclient >/dev/null 2>&1; then
    pass "emacsclient is available"
else
    fail "emacsclient not found in PATH"
fi

if emacsclient --eval 't' >/dev/null 2>&1; then
    pass "Emacs server is responding"
else
    fail "Emacs server is NOT responding (start with: emacs --daemon)"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 5: Cron Functions Exist
# ═══════════════════════════════════════════════════════════════════════════

section "Cron Functions"

check_function() {
    local func="$1"
    local result
    result=$(emacsclient --eval "(fboundp '$func)" 2>/dev/null)
    if [ "$result" = "t" ]; then
        pass "Function defined: $func"
        return 0
    else
        fail "Function NOT defined: $func"
        return 1
    fi
}

if emacsclient --eval 't' >/dev/null 2>&1; then
    check_function 'gptel-auto-evolve-run' || true
    check_function 'gptel-auto-workflow-run' || true
    check_function 'gptel-mementum-weekly-job' || true
    check_function 'gptel-benchmark-instincts-weekly-job' || true
else
    skip "Cannot check functions (Emacs server not responding)"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 6: Log File Writability
# ═══════════════════════════════════════════════════════════════════════════

section "Log File Writability"

TEST_LOG="$LOGDIR/test-write-$$.log"

if touch "$TEST_LOG" 2>/dev/null; then
    pass "Can create log files in $LOGDIR"
    rm -f "$TEST_LOG"
else
    fail "Cannot create log files in $LOGDIR"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 7: Check Recent Cron Execution (if logs exist)
# ═══════════════════════════════════════════════════════════════════════════

section "Recent Execution"

check_log() {
    local logname="$1"
    local logfile="$LOGDIR/$logname"
    
    if [ -f "$logfile" ]; then
        local size mtime
        size=$(stat -c%s "$logfile" 2>/dev/null || stat -f%z "$logfile" 2>/dev/null)
        mtime=$(stat -c%Y "$logfile" 2>/dev/null || stat -f%m "$logfile" 2>/dev/null)
        local now=$(date +%s)
        local age=$((now - mtime))
        
        if [ "$size" -gt 0 ]; then
            if [ "$age" -lt 86400 ]; then
                pass "$logname: ${size} bytes, modified $((age / 3600))h $((age % 3600 / 60))m ago"
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

check_log "auto-workflow.log"
check_log "mementum.log"
check_log "instincts.log"

# Check for cron mail (error indicator)
if [ -s "/var/mail/$USER" ]; then
    echo ""
    echo -e "${YELLOW}⚠ Cron mail detected - jobs may have failed${NC}"
    echo "  Check: cat /var/mail/$USER"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 8: Full Function Call Test (--full only)
# ═══════════════════════════════════════════════════════════════════════════

if [ "$FULL_TEST" = "--full" ]; then
    section "Full Function Test"
    
    echo "Running gptel-mementum-weekly-job (dry-run style)..."
    TEST_LOG_FULL="$LOGDIR/test-e2e-$$.log"
    
    if emacsclient --eval '(gptel-mementum-weekly-job)' >"$TEST_LOG_FULL" 2>&1; then
        pass "gptel-mementum-weekly-job executed"
        echo "  Output:"
        head -5 "$TEST_LOG_FULL" | sed 's/^/    /'
    else
        fail "gptel-mementum-weekly-job failed"
        echo "  Error:"
        cat "$TEST_LOG_FULL" | sed 's/^/    /'
    fi
    rm -f "$TEST_LOG_FULL"
else
    section "Full Function Test"
    skip "Use --full to run actual function tests"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "Summary: ${GREEN}PASS: $PASS${NC} ${RED}FAIL: $FAIL${NC} ${YELLOW}SKIP: $SKIP${NC}"
echo "═══════════════════════════════════════════════════════════════"

if [ $FAIL -gt 0 ]; then
    echo ""
    echo "Fix failures before cron jobs will work correctly."
    exit 1
fi

exit 0