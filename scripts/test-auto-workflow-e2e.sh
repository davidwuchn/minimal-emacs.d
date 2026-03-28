#!/bin/bash
#
# test-auto-workflow-e2e.sh
# End-to-end test for auto-workflow functionality
#

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "=== Auto-Workflow E2E Test ==="
echo ""

# Test 1: Check prerequisites
echo "[1/7] Checking prerequisites..."

# Check emacsclient
if ! command -v emacsclient &> /dev/null; then
    echo "  ✗ emacsclient not found"
    exit 1
fi
echo "  ✓ emacsclient found: $(which emacsclient)"

# Test 2: Check Emacs daemon
echo ""
echo "[2/7] Checking Emacs daemon..."
if emacsclient -e "t" &> /dev/null; then
    echo "  ✓ Emacs daemon is running"
else
    echo "  ⚠ Daemon not running (will auto-start with -a '')"
fi

# Test 3: Check required modules
echo ""
echo "[3/7] Checking required modules..."
for module in gptel-tools-agent.el gptel-auto-workflow-strategic.el; do
    if [ -f "lisp/modules/$module" ]; then
        echo "  ✓ $module exists"
    else
        echo "  ✗ $module missing"
        exit 1
    fi
done

# Test 4: Check cron configuration
echo ""
echo "[4/7] Checking cron configuration..."
if crontab -l | grep -q "gptel-auto-workflow"; then
    echo "  ✓ Auto-workflow cron job installed"
    crontab -l | grep "gptel-auto-workflow" | head -1 | sed 's/^/    /'
else
    echo "  ✗ Auto-workflow cron job not found"
    echo "    Run: ./scripts/install-cron.sh"
    exit 1
fi

# Test 5: Check directories
echo ""
echo "[5/7] Checking required directories..."
for dir in var/tmp/cron var/tmp/experiments; do
    if [ -d "$dir" ]; then
        echo "  ✓ $dir exists"
    else
        echo "  ⚠ $dir missing, creating..."
        mkdir -p "$dir"
    fi
done

# Test 6: Test Emacs can load modules
echo ""
echo "[6/7] Testing module loading..."
if emacsclient -e "(progn (load-file \"lisp/modules/gptel-tools-agent.el\") t)" &> /dev/null; then
    echo "  ✓ gptel-tools-agent.el loads successfully"
else
    echo "  ✗ Failed to load gptel-tools-agent.el"
    exit 1
fi

# Test 7: Check workflow status function exists
echo ""
echo "[7/7] Checking workflow functions..."
if emacsclient -e "(fboundp 'gptel-auto-workflow-status)" 2>/dev/null | grep -q "t"; then
    echo "  ✓ gptel-auto-workflow-status function exists"
else
    echo "  ✗ gptel-auto-workflow-status not found"
    exit 1
fi

if emacsclient -e "(fboundp 'gptel-auto-workflow-cron-safe)" 2>/dev/null | grep -q "t"; then
    echo "  ✓ gptel-auto-workflow-cron-safe function exists"
else
    echo "  ✗ gptel-auto-workflow-cron-safe not found"
    exit 1
fi

echo ""
echo "=== All E2E Tests Passed ==="
echo ""
echo "Next steps:"
echo "1. Test manual run: emacsclient -e '(gptel-auto-workflow-cron-safe)'"
echo "2. Check logs: tail -f var/tmp/cron/auto-workflow.log"
echo "3. Wait for cron job at next scheduled time (10:00, 14:00, 18:00)"
echo ""
echo "To trigger immediately:"
echo "  ./scripts/test-auto-workflow-e2e.sh && emacsclient -e '(gptel-auto-workflow-cron-safe)'"
