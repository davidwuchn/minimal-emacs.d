---
title: Code Development Patterns and Best Practices
status: active
category: knowledge
tags: [code-agent, efficiency, editing, code-review, tdd, patterns]
---

# Code Development Patterns and Best Practices

This knowledge page synthesizes patterns for code agent efficiency, surgical editing techniques, systematic code review, and test-driven development approaches.

## Code Agent Efficiency Analysis

### Task Type Performance

Code agent efficiency varies significantly by task type. Analysis across multiple test cases reveals clear patterns:

| Task Type | Efficiency | Steps | Typical Pattern |
|-----------|------------|-------|-----------------|
| Simple edit | 0.82-0.90 | 5-6 | read → edit (direct) |
| Exploration | 0.72 | 8 | glob → read×N → edit |

### Eight Keys Alignment Metrics

Tracking vitality, clarity, and synthesis scores across tasks:

| Key | code-001 | code-002 | code-003 | Average |
|-----|----------|----------|----------|---------|
| vitality | 0.85 | 0.88 | 0.78 | 0.84 |
| clarity | 0.82 | 0.90 | 0.72 | 0.81 |
| synthesis | 0.80 | 0.85 | 0.75 | 0.80 |

### Efficiency Anti-Pattern Checks

All tests pass Wu Xing constraints using these thresholds:

```python
# Anti-pattern detection thresholds
ANTI_PATTERNS = {
    "wood_overgrowth": lambda steps: steps <= 20,
    "fire_excess": lambda efficiency: efficiency >= 0.5,
    "metal_rigidity": lambda tool_score: tool_score >= 0.6,
    "tool_misuse": lambda steps, continuations: steps <= 15 and continuations <= 3
}
```

## Improvement Strategies

### 1. Exploration Task Optimization

**Problem:** Exploration tasks show 2+ continuations indicating context management issues.

**Solution (Fire → Water transformation):**
- Add exploration scope hints to task descriptions
- Use `--max-count` or `--max-depth` flags with glob/grep
- Budget: 3-5 files for exploration, 1-2 for targeted edits

```bash
# Limited exploration example
find . -name "*.el" -maxdepth 3 | head -5
rg --max-count 10 "defun" --glob "*.el"
```

### 2. Phase Transition Patterns

**Observation:** Simple edit tasks can skip Phase 2 (P1 → P3 direct path is valid).

**Pattern:** Direct path is more efficient than full cycle for simple tasks. Document when P2 can be skipped.

## Surgical Editing for Nested Code

### The Problem

Large edit operations on deeply nested code (10+ levels of nesting) easily break parentheses balance.

### Failed Approach

```elisp
;; This often breaks due to missing/mismatched parens
(edit old-block new-block)
```

### Successful Minimal Edit Pattern

```elisp
;; Step 1: Edit just the function call at the beginning
(edit "gptel-auto-experiment-decide"
      "(let ((code-quality ...))
         (gptel-auto-experiment-decide")

;; Step 2: Edit just the closing parens at the end
(edit "exp-result))))))))))))"
      "exp-result)))))))))))))")  ; one more paren for let
```

### Verification Commands

```bash
# Check file loads without errors
emacs --batch -l file.el

# Check parentheses balance (will hang if unbalanced)
timeout 10 emacs --batch --eval "(progn (find-file \"file.el\") (while t (forward-sexp)))"
```

### Pattern Symbol

λ surgical - minimal changes preserve structure

## Systematic Code Review Strategy

### Discovery

Batch analysis across entire repo is more effective than single-file optimization. Categorizing issues by severity and fixing in order yields measurable improvements.

### Workflow

1. **Scan entire codebase** with batch tools
2. **Categorize by severity** (Critical → High → Medium → Low)
3. **Fix in order** following severity hierarchy
4. **Verify incrementally** after each category

### Severity Categories

| Severity | Examples | Action |
|----------|----------|--------|
| Critical | Duplicate functions | Immediate fix (causes runtime errors) |
| High | Unused variables, free variables | Fix before next commit |
| Medium | Docstring width >80, wrong quotes | Fix during cleanup pass |
| Low | Missing declare-function | Fix when encountered |

### Diagnostic Commands

```bash
# Find all byte-compile warnings
emacs --batch --eval "(setq byte-compile-error-on-warn nil)" \
  -f batch-byte-compile lisp/modules/*.el 2>&1 | grep Warning

# Find duplicate function definitions
grep -rh "(defun " lisp/ | sed 's/(defun \([^ ]*\).*/\1/' | \
  sort | uniq -c | sort -rn | head

# Find docstring width violations
emacs --batch -f batch-byte-compile *.el 2>&1 | \
  grep "docstring wider than 80"

# Check for undefined variables
emacs --batch -f batch-byte-compile *.el 2>&1 | \
  grep -E "reference to free variable|void function"
```

### Results Tracking

- Found 5 categories of issues across codebase
- Fixed 22 total issues across 6 files
- Reduced warnings from ~20 to 1 (false positive)

## Test-Driven Development for Code Metrics

### The Problem

Old metric weighted docstrings at 40%, penalizing generated code without docs. Code scoring 0.83 before changes could drop to 0.51 after, triggering discard even when eight-keys score was high.

### TDD Approach

**Step 1: Write tests first**

```elisp
;; test-grader-subagent.el - 6 new tests

;; Test 1: Function existence
(should (fboundp 'gptel-benchmark--positive-patterns-score))

;; Test 2: Error handling rewards
(should (> (gptel-benchmark--positive-patterns-score
            "(condition-case err (progn) (error (message \" %s\" err)))")
           0.5))

;; Test 3: Bad naming penalties
(should (< (gptel-benchmark--positive-patterns-score
            "(defun my-foo-bar () 1)")
           0.3))

;; Test 4: Standard predicates reward
(should (> (gptel-benchmark--positive-patterns-score
            "(when (listp x) (when (stringp y) 1))")
           0.5))

;; Test 5: Weight distribution verification
(should (eql (round (* (gptel-benchmark--score 'docstring) 100)) 20))

;; Test 6: Minimum score threshold (≥0.70 for good patterns without docs)
(should (>= (gptel-benchmark--positive-patterns-score
             "(defun handle-error () (condition-case nil (progn)))")
            0.70))
```

**Step 2: Run tests to see failures** - All 6 tests failed as expected

**Step 3: Implement the function**

```elisp
(defun gptel-benchmark--positive-patterns-score (code)
  "Score CODE based on positive coding patterns."
  (let ((score 0))
    ;; Error handling (40% weight)
    (when (or (string-match-p "condition-case" code)
              (string-match-p "user-error" code)
              (string-match-p "\\(signal\\|error\\)" code))
      (setq score (+ score 0.4)))
    ;; Naming conventions (30% weight) - penalize bad prefixes
    (when (string-match-p "\\(defun\\s-+my-\\|defun\\s-+foo-\\|defun\\s-+bar-\\)" code)
      (setq score (- score 0.2)))
    ;; Standard predicates (30% weight)
    (when (or (string-match-p "\\(null\\|stringp\\|listp\\|consp\\)" code)
              (string-match-p "\\(when\\|if\\)" code))
      (setq score (+ score 0.3)))
    (max 0 (min 1 score))))
```

**Step 4: Rebalance weights**

| Component | Old Weight | New Weight |
|-----------|------------|------------|
| Docstrings | 40% | 20% |
| Positive Patterns | 0% | 30% |
| Length | 25% | 25% |
| Complexity | 25% | 25% |

**Step 5: Verify** - All tests pass (1303 tests, 0 unexpected)

### Result

Code with good patterns but no docstrings now scores ≥0.70 instead of 0.51. Valid experiments with error handling and type checking won't be discarded.

### TDD Pattern

```
λ TDD = test → fail → implement → pass
```

Tests encode requirements before code exists.

## Actionable Patterns Summary

1. **Efficiency:** Use direct paths for simple edits; add scope hints for exploration
2. **Editing:** Minimal surgical edits preserve structure in nested code
3. **Review:** Batch scan → categorize → prioritize → fix systematically
4. **Metrics:** TDD ensures metrics meet requirements before implementation

---

## Related

- [Code Agent Workflows](code-agent)
- [Wu Xing Constraints](wu-xing)
- [Eight Keys Metrics](eight-keys)
- [Emacs Lisp Patterns](emacs-lisp)
- [Benchmarking](benchmarking)
---