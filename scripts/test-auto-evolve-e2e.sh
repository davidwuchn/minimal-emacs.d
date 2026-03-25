#!/usr/bin/env bash

# test-auto-evolve-e2e.sh
# End-to-end test for auto-evolve system
#
# Tests:
# 1. Function exists
# 2. Branch creation
# 3. Simple improvement (mock)
# 4. Verification script exists
# 5. Git push capability
#
# Usage:
#   ./scripts/test-auto-evolve-e2e.sh [--full]

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

pass() { echo -e "${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }
skip() { echo -e "${YELLOW}○${NC} $1"; SKIP=$((SKIP + 1)); }
section() { echo ""; echo "=== $1 ==="; }

echo "═══════════════════════════════════════════════════════════════"
echo "         AUTO-EVOLVE E2E TEST"
echo "═══════════════════════════════════════════════════════════════"

ORIGINAL_BRANCH=$(git branch --show-current)

# ═══════════════════════════════════════════════════════════════════════════
# Test 1: Emacs Server
# ═══════════════════════════════════════════════════════════════════════════

section "Emacs Server"

if emacsclient --eval "t" >/dev/null 2>&1; then
    pass "Emacs server is running"
else
    fail "Emacs server not running - start Emacs first"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: Function Exists
# ═══════════════════════════════════════════════════════════════════════════

section "Function Check"

if emacsclient --eval "(fboundp 'gptel-auto-evolve-run)" 2>/dev/null | grep -q "t"; then
    pass "gptel-auto-evolve-run is defined"
else
    fail "gptel-auto-evolve-run is NOT defined"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 2: Git Configuration
# ═══════════════════════════════════════════════════════════════════════════

section "Git Configuration"

if git rev-parse --git-dir >/dev/null 2>&1; then
    pass "In git repository"
else
    fail "Not in git repository"
fi

if [ -n "$ORIGINAL_BRANCH" ]; then
    pass "Current branch: $ORIGINAL_BRANCH"
else
    fail "Could not detect current branch"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 3: Verify Script
# ═══════════════════════════════════════════════════════════════════════════

section "Verification Script"

VERIFY_SCRIPT="$DIR/scripts/verify-nucleus.sh"
if [ -x "$VERIFY_SCRIPT" ]; then
    pass "Verify script exists and is executable"
else
    fail "Verify script not found or not executable: $VERIFY_SCRIPT"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 4: Target Files
# ═══════════════════════════════════════════════════════════════════════════

section "Target Files"

for target in "gptel-ext-retry.el" "gptel-ext-context.el" "gptel-tools-code.el"; do
    target_path="$DIR/lisp/modules/$target"
    if [ -f "$target_path" ]; then
        pass "Target exists: $target"
    else
        fail "Target missing: $target"
    fi
done

# ═══════════════════════════════════════════════════════════════════════════
# Test 5: Dry Run (create and delete test branch)
# ═══════════════════════════════════════════════════════════════════════════

section "Branch Creation Test"

TEST_BRANCH="auto-evolve-test-$$"

if git checkout -b "$TEST_BRANCH" 2>/dev/null; then
    pass "Can create test branch: $TEST_BRANCH"
    
    if git push origin "$TEST_BRANCH" 2>/dev/null; then
        pass "Can push to origin"
        git push origin --delete "$TEST_BRANCH" 2>/dev/null || true
    else
        skip "Cannot push to origin (check SSH/permissions)"
    fi
    
    git checkout "$ORIGINAL_BRANCH" 2>/dev/null
    git branch -D "$TEST_BRANCH" 2>/dev/null || true
    pass "Branch cleanup complete"
else
    fail "Cannot create test branch"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Test 6: Full Run (--full only)
# ═══════════════════════════════════════════════════════════════════════════

if [ "$1" = "--full" ]; then
    section "Full Auto-Evolve Run"
    
    echo "Running gptel-auto-evolve-run..."
    echo "This will create a branch, attempt improvements, and push."
    echo ""
    
    LOG_FILE="$DIR/var/tmp/cron/auto-evolve-e2e-$$.log"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    if emacsclient --eval "(gptel-auto-evolve-run)" > "$LOG_FILE" 2>&1; then
        pass "Auto-evolve completed"
        echo "Log:"
        cat "$LOG_FILE" | head -20 | sed 's/^/    /'
    else
        fail "Auto-evolve failed"
        echo "Error log:"
        cat "$LOG_FILE" | sed 's/^/    /'
    fi
    
    rm -f "$LOG_FILE"
else
    section "Full Run"
    skip "Use --full to run actual auto-evolve cycle"
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
    echo "Fix failures before auto-evolve will work."
    exit 1
fi

exit 0