#!/usr/bin/env bash
# run-auto-workflow.sh - Run auto-workflow via emacsclient
#
# Usage:
#   ./scripts/run-auto-workflow.sh        # Start workflow
#   ./scripts/run-auto-workflow.sh status # Check status
#
# Uses emacsclient with user's Emacs daemon (has API keys, magit, gptel).
# If daemon not running, -a '' starts it automatically.
#
# IMPORTANT: Workflow runs async, daemon stays responsive.
# Check status anytime with: ./scripts/run-auto-workflow.sh status

set -e
cd "$(dirname "$0")/.."

case "${1:-}" in
  status)
    emacsclient -a '' -e '(progn 
      (require (quote magit))
      (require (quote json))
      (load-file "~/.emacs.d/lisp/modules/gptel-tools-agent.el")
      (gptel-auto-workflow-status))' 2>&1
    ;;
  *)
    echo "=== Starting Auto-Workflow ===" 
    echo "Started: $(date)"
    emacsclient -a '' -e '(progn 
      (require (quote magit))
      (require (quote json))
      (load-file "~/.emacs.d/lisp/modules/gptel-tools-agent.el")
      (gptel-auto-workflow-run-async))' 2>&1
    echo ""
    echo "Workflow started. Check status with:"
    echo "  ./scripts/run-auto-workflow.sh status"
    echo ""
    echo "Results: var/tmp/experiments/$(date +%Y-%m-%d)/results.tsv"
    ;;
esac