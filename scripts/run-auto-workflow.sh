#!/usr/bin/env bash

# run-auto-workflow.sh
# Run auto-workflow optimization experiments
#
# Usage:
#   ./scripts/run-auto-workflow.sh           # Run with default targets
#   ./scripts/run-auto-workflow.sh --dry-run # Just print what would run
#
# Logs: var/tmp/experiments/YYYY-MM-DD/results.tsv
#
# NOTE: Requires running Emacs server or will start daemon automatically.

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

LOGDIR="$DIR/var/tmp/cron"
mkdir -p "$LOGDIR"

if [ "$1" = "--dry-run" ]; then
    echo "=== Auto-Workflow Dry Run ==="
    echo ""
    echo "Targets: gptel-ext-retry.el, gptel-ext-context.el, gptel-tools-code.el"
    echo "Time budget: 10 minutes per experiment"
    echo "Max experiments per target: 10"
    echo ""
    echo "Results will be logged to: var/tmp/experiments/YYYY-MM-DD/results.tsv"
    echo ""
    echo "To run: $0"
    exit 0
fi

echo "=== Running Auto-Workflow ===" 
echo "Started: $(date)"
echo ""

# Check if Emacs server is running
if ! emacsclient -e t >/dev/null 2>&1; then
    echo "Starting Emacs daemon..."
    emacs --daemon
    sleep 3
fi

# Run via emacsclient (uses user's gptel config)
emacsclient -e '(gptel-auto-workflow-run-sync)' 2>&1 | tee "$LOGDIR/auto-workflow.log"

echo ""
echo "Completed: $(date)"
echo "Results: var/tmp/experiments/$(date +%Y-%m-%d)/results.tsv"