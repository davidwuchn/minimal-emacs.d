#!/bin/bash
# verify-integration.sh - Full integration verification
#
# Runs all tests:
#   1. Unit tests (ERT)
#   2. Integration tests (ERT)
#   3. E2E tests (shell)

# Find root directory (parent of scripts/)
# Try to detect from script location, fall back to current git repo
if [[ -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_PATH="${BASH_SOURCE[0]}"
else
    SCRIPT_PATH="$0"
fi

if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" pwd 2>/dev/null || echo "")"
else
    SCRIPT_DIR=""
fi

# Fallback: find git root
if [[ -z "$SCRIPT_DIR" || ! -d "$SCRIPT_DIR" ]]; then
    GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
    if [[ -n "$GIT_ROOT" ]]; then
        SCRIPT_DIR="$GIT_ROOT/scripts"
    else
        SCRIPT_DIR="$HOME/.emacs.d/scripts"
    fi
fi

ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

cd "$ROOT_DIR"

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local name="$1"
    local cmd="$2"
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  $name"
    echo "═══════════════════════════════════════════════════════════════"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if eval "$cmd"; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo "✓ $name PASSED"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo "✗ $name FAILED"
    fi
}

# Unit Tests
echo ""
echo "═════════════════════════════════════════════════════════════════════"
echo "         LEVEL 1: UNIT TESTS"
echo "═════════════════════════════════════════════════════════════════════"

run_test "Benchmark Unit Tests (ERT)" \
    "emacs --batch -Q -L . -L lisp -L lisp/modules \
        -l lisp/modules/gptel-benchmark-tests.el \
        -f ert-run-tests-batch-and-exit 2>&1 | grep -q '0 unexpected'"

run_test "Skill Benchmark Tests (ERT)" \
    "emacs --batch -Q -L . -L lisp -L lisp/modules \
        -l tests/test-gptel-skill-benchmark.el \
        -f ert-run-tests-batch-and-exit 2>&1 | grep -q '0 unexpected'"

# Integration Tests
echo ""
echo "═════════════════════════════════════════════════════════════════════"
echo "         LEVEL 2: INTEGRATION TESTS"
echo "═════════════════════════════════════════════════════════════════════"

run_test "Integration Tests (ERT)" \
    "emacs --batch -Q -L . -L lisp -L lisp/modules \
        -l lisp/modules/gptel-benchmark-integration-tests.el \
        -f ert-run-tests-batch-and-exit 2>&1 | grep -q '0 unexpected'"

# E2E Tests
echo ""
echo "═════════════════════════════════════════════════════════════════════"
echo "         LEVEL 3: E2E TESTS"
echo "═════════════════════════════════════════════════════════════════════"

run_test "Auto-Evolve Cycle (E2E)" \
    "bash ${SCRIPT_DIR}/test-auto-evolve-cycle.sh 2>&1 | tail -5 | grep -q 'PASSED'"

run_test "Mementum Integration (E2E)" \
    "bash ${SCRIPT_DIR}/test-mementum-integration.sh 2>&1 | tail -5 | grep -q 'PASSED'"

run_test "CI Local Simulation (E2E)" \
    "bash ${SCRIPT_DIR}/test-ci-local.sh 2>&1 | tail -5 | grep -q 'PASSED'"

# Summary
echo ""
echo "═════════════════════════════════════════════════════════════════════"
echo "         VERIFICATION SUMMARY"
echo "═════════════════════════════════════════════════════════════════════"

echo ""
echo "  Total:   $TOTAL_TESTS"
echo "  Passed:  $PASSED_TESTS"
echo "  Failed:  $FAILED_TESTS"
echo ""

if [ "$FAILED_TESTS" -eq 0 ]; then
    echo "═════════════════════════════════════════════════════════════════════"
    echo "         ALL TESTS PASSED ✓"
    echo "═════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "═════════════════════════════════════════════════════════════════════"
    echo "         SOME TESTS FAILED ✗"
    echo "═════════════════════════════════════════════════════════════════════"
    exit 1
fi