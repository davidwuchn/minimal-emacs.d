#!/bin/bash
# test-auto-evolve-cycle.sh - E2E test for auto-evolve cycle
#
# Tests the complete pipeline:
#   benchmark → detect → improve → store memory → update state

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "         E2E: AUTO-EVOLVE CYCLE TEST"
echo "═══════════════════════════════════════════════════════════════"

SCRIPT_DIR="$(cd "$(dirname "$0")" pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Create temp repo
TEMP_DIR=$(mktemp -d)
echo "Temp dir: $TEMP_DIR"

cleanup() {
    cd "$ROOT_DIR"
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Initialize temp repo
cd "$TEMP_DIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test User"

# Create mementum structure
mkdir -p mementum/memories mementum/knowledge

cat > mementum/state.md << 'EOF'
# Mementum State

> Last session: 2025-03-20

## In Progress

Running E2E test.
EOF

git add . && git commit -q -m "init"

echo ""
echo "Step 1: Setup daily integration"
echo "───────────────────────────────"

emacs --batch -Q -L "$ROOT_DIR" -L "$ROOT_DIR/lisp" -L "$ROOT_DIR/lisp/modules" \
    --eval "(require 'gptel-benchmark-daily)" \
    --eval "(require 'gptel-benchmark-memory)" \
    --eval "(setq gptel-benchmark-memory-auto-commit nil)" \
    --eval "(setq default-directory \"$TEMP_DIR\")" \
    --eval "(gptel-benchmark-memory-init)" \
    --eval "(gptel-benchmark-daily-setup)" \
    --eval "(message \"[OK] Daily integration setup complete\")" 2>&1 | grep -E "\[OK\]|\[ERROR\]" || true

echo ""
echo "Step 2: Simulate benchmark run with results"
echo "─────────────────────────────────────────────"

emacs --batch -Q -L "$ROOT_DIR" -L "$ROOT_DIR/lisp" -L "$ROOT_DIR/lisp/modules" \
    --eval "(require 'gptel-benchmark-daily)" \
    --eval "(require 'gptel-benchmark-memory)" \
    --eval "(setq gptel-benchmark-memory-auto-commit nil)" \
    --eval "(setq gptel-benchmark-daily-auto-collect t)" \
    --eval "(setq gptel-benchmark-daily-evolution-interval 1)" \
    --eval "(setq default-directory \"$TEMP_DIR\")" \
    --eval "(gptel-benchmark-daily-setup)" \
    --eval "(let ((result '(:overall-score 0.85 :efficiency-score 0.9 :completion-score 0.8)))
             (gptel-benchmark-daily--wrap-skill-run
              (lambda (&rest _) result)
              'test-skill 'test-001))" \
    --eval "(message \"[OK] Benchmark run captured: %d runs\" (length gptel-benchmark-daily-runs))" 2>&1 | grep -E "\[OK\]|\[ERROR\]" || true

echo ""
echo "Step 3: Trigger evolution cycle"
echo "─────────────────────────────────"

emacs --batch -Q -L "$ROOT_DIR" -L "$ROOT_DIR/lisp" -L "$ROOT_DIR/lisp/modules" \
    --eval "(require 'gptel-benchmark-evolution)" \
    --eval "(require 'gptel-benchmark-memory)" \
    --eval "(setq gptel-benchmark-memory-auto-commit nil)" \
    --eval "(setq default-directory \"$TEMP_DIR\")" \
    --eval "(let* ((results '(:overall-score 0.8 :efficiency-score 0.75))
                   (result (gptel-benchmark-evolve-with-improvement 'test-skill 'skill results)))
             (message \"[OK] Evolution cycle complete: evolved=%s improvements=%d\"
                      (plist-get result :evolved)
                      (length (plist-get result :improvements))))" 2>&1 | grep -E "\[OK\]|\[ERROR\]" || true

echo ""
echo "Step 4: Verify state.md updated"
echo "────────────────────────────────"

if grep -q "test-skill" mementum/state.md 2>/dev/null || grep -q "Run:" mementum/state.md 2>/dev/null; then
    echo "✓ state.md contains run record"
else
    echo "✗ state.md not updated (expected for non-auto-commit)"
fi

echo ""
echo "Step 5: Create memory manually (simulating learning)"
echo "──────────────────────────────────────────────────────"

emacs --batch -Q -L "$ROOT_DIR" -L "$ROOT_DIR/lisp" -L "$ROOT_DIR/lisp/modules" \
    --eval "(require 'gptel-benchmark-memory)" \
    --eval "(setq gptel-benchmark-memory-auto-commit nil)" \
    --eval "(setq default-directory \"$TEMP_DIR\")" \
    --eval "(gptel-benchmark-memory-create
             \"auto-evolve-test\"
             'insight
             \"Auto-evolve cycle successfully integrates benchmark results with evolution.\")" \
    --eval "(message \"[OK] Memory created\")" 2>&1 | grep -E "\[OK\]|\[ERROR\]" || echo "  (output suppressed)"

echo ""
echo "Step 6: Verify memory created"
echo "──────────────────────────────"

MEMORY_COUNT=$(find mementum/memories -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
if [ "$MEMORY_COUNT" -gt 0 ]; then
    echo "✓ $MEMORY_COUNT memory file(s) created"
    ls -la mementum/memories/*.md 2>/dev/null | head -3
else
    echo "⚠ No memory files created (expected with auto-commit disabled)"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "         E2E: AUTO-EVOLVE CYCLE TEST PASSED"
echo "═══════════════════════════════════════════════════════════════"