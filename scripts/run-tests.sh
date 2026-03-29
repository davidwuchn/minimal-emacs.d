#!/usr/bin/env bash

# run-tests.sh
# Run all ERT tests in tests/ directory
#
# Usage:
#   ./scripts/run-tests.sh              # Run all tests
#   ./scripts/run-tests.sh grader       # Run tests matching pattern
#
# Returns 0 if all tests pass, 1 if any fail.

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

PATTERN="${1:-t}"

echo "Running ERT tests (pattern: $PATTERN)..."
echo ""

# Run tests and capture output
emacs --batch -Q \
  -L "$DIR" \
  -L "$DIR/lisp" \
  -L "$DIR/lisp/modules" \
  -L "$DIR/packages/gptel" \
  -L "$DIR/packages/gptel-agent" \
  -L "$DIR/packages/magit/lisp" \
  -L "$DIR/tests" \
  -l ert \
  $(find tests -name "test-*.el" -exec echo "-l {}" \;) \
  --eval "(ert-run-tests-batch-and-exit \"$PATTERN\")" 2>&1 | tee /tmp/ert-output.txt

# Check for success
if grep -q "0 unexpected" /tmp/ert-output.txt 2>/dev/null; then
    echo ""
    echo "✓ All tests passed"
    exit 0
else
    echo ""
    echo "✗ Some tests failed or unexpected results"
    exit 1
fi