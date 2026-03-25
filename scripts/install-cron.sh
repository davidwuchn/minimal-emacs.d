#!/usr/bin/env bash

# install-cron.sh
# Install cron jobs for autonomous operation
#
# Usage:
#   ./scripts/install-cron.sh [--dry-run]
#
# Options:
#   --dry-run    Show what would be installed without modifying crontab

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRON_FILE="$DIR/cron.d/auto-workflow"

echo "=== Installing Cron Jobs for Autonomous Operation ==="
echo ""

# Check if cron file exists
if [ ! -f "$CRON_FILE" ]; then
    echo "Error: Cron file not found: $CRON_FILE"
    exit 1
fi

# Create required directories
echo "Creating required directories..."
mkdir -p "$DIR/var/tmp/cron"
mkdir -p "$DIR/var/tmp/experiments"
echo "  ✓ var/tmp/cron/"
echo "  ✓ var/tmp/experiments/"
echo ""

# Check current crontab
echo "Current crontab:"
echo "---"
crontab -l 2>/dev/null || echo "(empty)"
echo "---"
echo ""

if [ "$1" = "--dry-run" ]; then
    echo "DRY RUN - Would install:"
    echo "---"
    cat "$CRON_FILE" | grep -v "^#" | grep -v "^$" | grep -v "^SHELL" | grep -v "^LOGDIR" | grep -v "@reboot"
    echo "---"
    echo ""
    echo "To install for real, run:"
    echo "  ./scripts/install-cron.sh"
else
    echo "Installing crontab from: $CRON_FILE"
    crontab "$CRON_FILE"
    echo "✓ Crontab installed"
    echo ""
    echo "Installed jobs:"
    crontab -l | grep -v "^#" | grep -v "^$" | grep -v "^SHELL" | grep -v "^LOGDIR" | grep -v "@reboot"
    echo ""
    echo "Logs will be written to: $DIR/var/tmp/cron/"
fi

echo ""
echo "=== Scheduled Jobs ==="
echo ""
echo "| Schedule         | Function                              | Log File         |"
echo "|------------------|---------------------------------------|------------------|"
echo "| Daily 2:00 AM    | gptel-auto-workflow-run-async        | auto-workflow.log|"
echo "| Weekly Sun 4:00 AM| gptel-mementum-weekly-job            | mementum.log     |"
echo "| Weekly Sun 5:00 AM| gptel-benchmark-instincts-weekly-job | instincts.log    |"
echo ""
echo "=== Prerequisites ==="
echo ""
echo "1. Emacs daemon must be running:"
echo "   emacs --daemon"
echo ""
echo "2. For overnight experiments, edit targets in:"
echo "   docs/auto-workflow-program.md"
echo ""
echo "3. Check logs:"
echo "   tail -f var/tmp/cron/*.log"
echo ""
echo "4. Verify setup:"
echo "   ./scripts/test-cron-e2e.sh"
echo ""
echo "Done."