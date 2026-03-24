#!/usr/bin/env bash

# run-tests.sh
# Run all ERT tests in tests/ directory
#
# Usage:
#   ./scripts/run-tests.sh              # Run all tests
#   ./scripts/run-tests.sh grader       # Run tests matching pattern

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

PATTERN="${1:-t}"

echo "Running ERT tests (pattern: $PATTERN)..."
echo ""

emacs --batch -Q \
  -L "$DIR" \
  -L "$DIR/lisp" \
  -L "$DIR/lisp/modules" \
  -L "$DIR/tests" \
  -l ert \
  $(find tests -name "test-*.el" -exec echo "-l {}" \;) \
  --eval "(ert-run-tests-batch-and-exit '$PATTERN)"

echo ""
echo "Done."