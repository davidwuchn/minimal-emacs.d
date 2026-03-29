#!/usr/bin/env bash

# run-tests-client.sh
# Run ERT tests via emacsclient (for tests that need interactive Emacs)
#
# Usage:
#   ./scripts/run-tests-client.sh              # Run all tests
#   ./scripts/run-tests-client.sh treesit      # Run treesit tests
#
# Requires a running Emacs server (M-x server-start or emacs --daemon)

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATTERN="${1:-t}"

echo "Running ERT tests via emacsclient (pattern: $PATTERN)..."
echo ""

# Check if emacsclient can connect
if ! emacsclient -e "1" &>/dev/null; then
    echo "Error: Cannot connect to Emacs server."
    echo "Start one with: emacs --daemon"
    echo "Or in Emacs: M-x server-start"
    exit 1
fi

# Run tests and get result
RESULT=$(emacsclient -e "
(progn
  (require 'ert)
  (dolist (f (directory-files \"$DIR/tests\" t \"^test-.*\\.el$\"))
    (load-file f))
  (let* ((stats (ert-run-tests \"$PATTERN\" (lambda (_event-type &rest _args) nil))))
    (format \"completed=%d expected=%d unexpected=%d skipped=%d\"
            (ert-stats-completed stats)
            (ert-stats-completed-expected stats)
            (ert-stats-completed-unexpected stats)
            (ert-stats-skipped stats))))" 2>&1)

echo "$RESULT"

# Parse result
if echo "$RESULT" | grep -q "unexpected=0"; then
    echo ""
    echo "✓ All tests passed"
    exit 0
else
    echo ""
    echo "✗ Some tests failed"
    exit 1
fi