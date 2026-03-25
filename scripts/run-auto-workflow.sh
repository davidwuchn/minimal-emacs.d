#!/usr/bin/env bash
# run-auto-workflow.sh - Run auto-workflow via emacsclient
#
# Usage: ./scripts/run-auto-workflow.sh
#
# Uses emacsclient with user's Emacs daemon (has API keys, magit, gptel).
# If daemon not running, -a '' starts it automatically.

set -e
cd "$(dirname "$0")/.."

echo "=== Auto-Workflow ===" 
echo "Started: $(date)"

emacsclient -a '' -e '(progn (load-file "~/.emacs.d/lisp/modules/gptel-tools-agent.el") (gptel-auto-workflow-run-sync))' 2>&1

echo ""
echo "Completed: $(date)"
echo "Results: var/tmp/experiments/$(date +%Y-%m-%d)/results.tsv"