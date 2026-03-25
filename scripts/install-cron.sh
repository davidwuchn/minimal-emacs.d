#!/usr/bin/env bash

# install-cron.sh
# Install cron jobs for autonomous operation
#
# Usage:
#   ./scripts/install-cron.sh [--dry-run]
#
# Options:
#   --dry-run    Show what would be installed without modifying crontab
#
# Auto-detects machine and uses appropriate schedule:
#   - macOS (imacpro): cron.d/auto-workflow (1:00, 5:00 AM)
#   - Pi5:             cron.d/auto-workflow-pi5 (11:00 PM, 3:00 AM)

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Detect machine and select appropriate cron file
HOSTNAME=$(hostname)
if echo "$HOSTNAME" | grep -q "imacpro\|macbook\|mac"; then
    CRON_FILE="$DIR/cron.d/auto-workflow"
    MACHINE="macOS"
elif echo "$HOSTNAME" | grep -q "pi5\|raspberrypi"; then
    CRON_FILE="$DIR/cron.d/auto-workflow-pi5"
    MACHINE="Pi5"
else
    # Default to auto-workflow, warn user
    CRON_FILE="$DIR/cron.d/auto-workflow"
    MACHINE="unknown"
fi

echo "=== Installing Cron Jobs for Autonomous Operation ==="
echo ""
echo "Detected machine: $HOSTNAME ($MACHINE)"
echo "Using cron file: $(basename $CRON_FILE)"
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
echo "=== Scheduled Jobs ($MACHINE) ==="
echo ""
if [ "$MACHINE" = "Pi5" ]; then
    echo "Pi5: Heavy 24/7 usage (headless, always on)"
    echo ""
    echo "| Schedule                       | Function                              |"
    echo "|--------------------------------|---------------------------------------|"
    echo "| 11PM, 3AM, 7AM, 11AM, 3PM, 7PM| gptel-auto-workflow-run-async        |"
    echo "| Every 4 hours                  | gptel-auto-workflow-run-research     |"
    echo "| Weekly Sun 4:00 AM             | gptel-mementum-weekly-job            |"
    echo "| Weekly Sun 5:00 AM             | gptel-benchmark-instincts-weekly-job |"
    echo ""
    echo "Pi5: 6 workflow runs/day + 6 researcher runs/day"
else
    echo "macOS: Daylight hours only (when user is active)"
    echo ""
    echo "| Schedule          | Function                              |"
    echo "|-------------------|---------------------------------------|"
    echo "| 10AM, 2PM, 6PM    | gptel-auto-workflow-run-async        |"
    echo "| Every 4 hours     | gptel-auto-workflow-run-research     |"
    echo "| Weekly Sun 4:00 AM| gptel-mementum-weekly-job            |"
    echo "| Weekly Sun 5:00 AM| gptel-benchmark-instincts-weekly-job |"
    echo ""
    echo "macOS: 3 workflow runs/day + 6 researcher runs/day"
fi
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