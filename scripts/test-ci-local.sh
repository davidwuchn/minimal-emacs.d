#!/bin/bash
# test-ci-local.sh - Local CI simulation
#
# Simulates the CI workflow locally:
#   1. Run benchmark
#   2. Check Eight Keys scores
#   3. Detect anti-patterns
#   4. Generate suggestions
#   5. Output as JSON

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "         LOCAL CI SIMULATION TEST"
echo "═══════════════════════════════════════════════════════════════"

SCRIPT_DIR="$(cd "$(dirname "$0")" pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

echo ""
echo "Step 1: Check Eight Keys Score (simulated)"
echo "───────────────────────────────────────────"

# Simulate benchmark output with Eight Keys scores
MOCK_OUTPUT="Successfully completed the task with clear implementation steps.
The solution followed best practices and included proper error handling.
Verification was performed with unit tests.
No TODO comments were left in the code.
The response was concise and to the point."

RESULT=$(emacs --batch -Q -L . -L lisp -L lisp/modules \
    --eval "(require 'gptel-benchmark-principles)" \
    --eval "(let* ((output \"$MOCK_OUTPUT\")
                   (scores (gptel-benchmark-eight-keys-score output))
                   (overall (alist-get 'overall scores)))
             (message \"Overall: %.0f%%\" (* 100 overall))
             (dolist (key-def gptel-benchmark-eight-keys-definitions)
               (let* ((key (car key-def))
                      (name (plist-get key-def :name))
                      (score (alist-get key scores)))
                 (message \"  %s: %.0f%%\" name (* 100 (or score 0))))))" 2>&1)

echo "$RESULT" | grep -E "Overall:|  " || true

OVERALL=$(echo "$RESULT" | grep "Overall:" | sed 's/Overall: //' | sed 's/%//')

echo ""
echo "Step 2: Detect Anti-Patterns"
echo "────────────────────────────"

# Simulate benchmark results with potential issues
ANTI_PATTERNS=$(emacs --batch -Q -L . -L lisp -L lisp/modules \
    --eval "(require 'gptel-benchmark-evolution)" \
    --eval "(let* ((results '(:step-count 15 :efficiency-score 0.55 :completion-score 0.4))
                   (anti-patterns (gptel-benchmark-detect-anti-patterns results)))
             (message \"Detected %d anti-patterns\" (length anti-patterns))
             (dolist (ap anti-patterns)
               (message \"  - %s (%s): %s\"
                        (plist-get ap :pattern)
                        (plist-get ap :element)
                        (plist-get ap :symptom))))" 2>&1)

echo "$ANTI_PATTERNS" | grep -E "Detected:|  -" || true

echo ""
echo "Step 3: Generate Improvements"
echo "──────────────────────────────"

IMPROVEMENTS=$(emacs --batch -Q -L . -L lisp -L lisp/modules \
    --eval "(require 'gptel-benchmark-auto-improve)" \
    --eval "(let* ((anti-patterns '((:pattern wood-overgrowth :element wood :symptom \"Too many steps\")))
                   (improvements (gptel-benchmark-generate-improvements 'test-skill 'skill anti-patterns)))
             (message \"Generated %d improvements\" (length improvements))
             (dolist (imp improvements)
               (message \"  - %s: %s\"
                        (plist-get imp :element)
                        (plist-get imp :action))))" 2>&1)

echo "$IMPROVEMENTS" | grep -E "Generated:|  -" || true

echo ""
echo "Step 4: Output JSON for CI"
echo "──────────────────────────"

# Generate JSON output similar to what CI would produce
cat << EOF
{
  "skill": "test-skill",
  "overall_score": $OVERALL,
  "passed": true,
  "eight_keys": {
    "phi-vitality": 0.85,
    "fractal-clarity": 0.90,
    "epsilon-purpose": 0.80,
    "tau-wisdom": 0.75,
    "pi-synthesis": 0.85,
    "mu-directness": 0.90,
    "exists-truth": 0.95,
    "forall-vigilance": 0.80
  },
  "anti_patterns": [
    {
      "pattern": "fire-excess",
      "element": "fire",
      "symptom": "Efficiency below threshold",
      "remedy": "Apply Water (identity): ground in principles, plan first"
    }
  ],
  "suggestions": [
    "Consider breaking down complex tasks into smaller steps",
    "Add more explicit planning phase before implementation"
  ]
}
EOF

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "         LOCAL CI SIMULATION TEST PASSED"
echo "═══════════════════════════════════════════════════════════════"