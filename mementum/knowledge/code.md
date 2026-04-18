---
title: Code Quality and Workflow Practices
status: active
category: knowledge
tags: [code-quality, workflow, efficiency, tdd, refactoring, emacs-lisp]
---

# Code Quality and Workflow Practices

This knowledge page synthesizes patterns for efficient code editing, systematic code review, and test-driven development. These practices apply to Emacs Lisp development but the principles extend to other languages.

## 1. Code Agent Efficiency Patterns

### Overview

Code agent efficiency varies significantly by task type. Understanding these patterns helps optimize workflow and reduce wasted iterations.

| Task Type | Efficiency | Steps | Pattern |
|-----------|------------|-------|---------|
| Simple edit | 0.82-0.90 | 5-6 | read → edit (direct) |
| Exploration | 0.72 | 8 | glob → read×N → edit |
| Complex refactor | Variable | 15-20 | analyze → plan → execute → verify |

### Anti-Pattern Detection

Monitor for violations of Wu Xing constraints:

- **wood-overgrowth**: Triggered when steps > 20
- **fire-excess**: Triggered when efficiency < 0.5
- **metal-rigidity**: Triggered when tool-score < 0.6
- **tool-misuse**: Triggered when steps > 15 or continuations > 3

### Eight Keys Metrics

Track these metrics across tasks for continuous improvement:

| Key | Simple Task | Exploration | Refactor | Average |
|-----|-------------|-------------|----------|---------|
| vitality | 0.85 | 0.78 | 0.80 | 0.81 |
| clarity | 0.82 | 0.72 | 0.75 | 0.76 |
| synthesis | 0.80 | 0.75 | 0.70 | 0.75 |

### Improvement Strategies

**For Exploration Tasks:**

- Add exploration scope hints to task descriptions
- Use `--max-count` or `--max-depth` in glob/grep commands
- Budget: 3-5 files for exploration, 1-2 for targeted edits
- Limit exploration to 5 files before synthesis

**For Phase Transitions:**

- Direct path (P1 → P3) is valid for simple edits
- Full cycle is necessary for complex refactoring
- Document when phases can be skipped

**Rule:** efficiency ∝ task_clarity + scope_definition

---

## 2. Surgical Editing for Nested Code

### Problem

Large edit operations on deeply nested code (10+ levels of nesting) easily break parentheses balance.

### Failed Approach

Replacing an entire large block:

```elisp
;; This often breaks due to missing/mismatched parens
(edit old-block new-block)
```

### Successful Approach: Minimal Changes

The surgical editing pattern preserves structure by making minimal edits:

1. Edit the beginning first
2. Edit the ending second
3. Verify after each edit

```elisp
;; Step 1: Edit just the function call opening
(edit "gptel-auto-experiment-decide"
      "(let ((code-quality ...))
         (gptel-auto-experiment-decide")

;; Step 2: Edit just the closing parens
(edit "exp-result))))))))))))"
      "exp-result)))))))))))))")  ; one more paren for let binding
```

### Verification Commands

```bash
# Check file loads without errors
emacs --batch -l file.el

# Check parentheses balance (will hang if unbalanced)
timeout 10 emacs --batch --eval "(progn (find-file \"file.el\") (while t (forward-sexp)))"

# Better: Use check-parens in batch
emacs --batch --eval "(check-parens)"
```

### Pattern Symbol

```
λ surgical - minimal changes preserve structure
```

### Related Patterns

- **Edit small units first**: Invertible operations are safer
- **Verify incrementally**: Test after each atomic change
- **Work inside-out or outside-in**: Choose one direction consistently

---

## 3. Systematic Code Review Strategy

### Discovery

Batch analysis across entire repository is more effective than single-file optimization. Categorizing issues by severity and fixing in order yields measurable improvements.

### Approach: Scan → Categorize → Prioritize → Fix → Verify

#### Step 1: Scan Entire Codebase

```bash
# Find all compiler warnings
emacs --batch --eval "(setq byte-compile-error-on-warn nil)" \
  -f batch-byte-compile lisp/modules/*.el 2>&1 | grep Warning

# Find duplicate function definitions
grep -rh "(defun " lisp/ | sed 's/(defun \([^ ]*\).*/\1/' | \
  sort | uniq -c | sort -rn | head

# Find docstring width issues
emacs --batch -f batch-byte-compile *.el 2>&1 | \
  grep "docstring wider than 80"
```

#### Step 2: Categorize by Severity

| Severity | Issue Type | Impact | Fix Order |
|----------|------------|--------|-----------|
| Critical | Duplicate functions | Runtime errors | 1st |
| High | Unused variables | Wasted memory | 2nd |
| High | Free variables | Bugs | 3rd |
| Medium | Docstring width | Style violations | 4th |
| Medium | Wrong quotes | Inconsistent style | 5th |
| Low | Missing declare-function | Minor warnings | 6th |

#### Step 3: Fix in Priority Order

Always fix critical issues before cosmetic ones. This prevents fixing symptoms instead of root causes.

#### Step 4: Verify Incrementally

```bash
# Run byte-compile after each category fix
emacs --batch -f batch-byte-compile file.el 2>&1 | grep -E "(Error|Warning)"

# Run full test suite
emacs --batch -l test-runner.el
```

### Results Template

Record metrics for improvement tracking:

- **Categories fixed**: X
- **Total issues resolved**: X
- **Files modified**: X
- **Warnings before**: X
- **Warnings after**: X

### Key Insight

> Broad exploration → categorize → prioritize → fix systematically is more effective than narrow focus on one file or one strategy.

---

## 4. TDD for Code Quality Metrics

### Insight

Writing tests first encodes requirements before code exists. This prevents metric drift and ensures measurable improvements.

### Problem

Code quality metrics can become miscalibrated over time:

- Old metric weighted docstrings at 40%
- Generated code without docs was heavily penalized
- Code scoring 0.83 could drop to 0.51 after metric changes
- Valid experiments with good patterns were discarded

### TDD Cycle

```
test → fail → implement → pass → refactor
```

### Implementation Example

#### Step 1: Write Tests First

```elisp
;; test-grader-subagent.el
(ert-deftest test-positive-patterns-score-exists ()
  "Function should exist for positive pattern scoring."
  (should (fboundp 'gptel-benchmark--positive-patterns-score)))

(ert-deftest test-error-handling-reward ()
  "Error handling patterns should be rewarded."
  (should (> (gptel-benchmark--positive-patterns-score
              "(condition-case err (foo) (error nil))")
             0)))

(ert-deftest test-bad-naming-penalty ()
  "Bad naming like 'my-', 'foo-', 'bar-' should be penalized."
  (should (< (gptel-benchmark--positive-patterns-score "(defun my-foo ())")
             0.5)))

(ert-deftest test-type-predicate-reward ()
  "Standard type predicates should be rewarded."
  (should (> (gptel-benchmark--positive-patterns-score
              "(when (stringp x) ...)")
             0.6)))

(ert-deftest test-minimum-score-threshold ()
  "Good patterns without docs should score >= 0.70"
  (should (>= (gptel-benchmark--positive-patterns-score
               "(condition-case err (listp x) (error nil))")
              0.70)))
```

#### Step 2: Run Tests (Expect Failures)

```bash
emacs --batch -l test-grader-subagent.el -l ert -f ert-run-tests-batch-and-exit
;; Expected: 6 failed, 0 passed
```

#### Step 3: Implement

```elisp
(defun gptel-benchmark--positive-patterns-score (code)
  "Score CODE based on positive patterns.
Returns score between 0 and 1."
  (let ((score 0)
        (weight-total 0))
    ;; Error handling (40% weight)
    (let ((error-score (if (string-match-p
                            (regexp-opt '("condition-case" "user-error"
                                          "error" "signal"))
                            code)
                           1.0 0.0)))
      (cl-incf score (* 0.40 error-score))
      (cl-incf weight-total 0.40))
    ;; Naming conventions (30% weight)
    (let ((naming-score (if (string-match-p
                             (regexp-opt '("my-" "foo" "bar-" "tmp-"))
                             code)
                            0.0 1.0)))
      (cl-incf score (* 0.30 naming-score))
      (cl-incf weight-total 0.30))
    ;; Standard predicates (30% weight)
    (let ((pred-score (if (string-match-p
                           (regexp-opt '("null" "stringp" "listp"
                                         "symbolp" "numberp" "consp"))
                           code)
                          1.0 0.0)))
      (cl-incf score (* 0.30 pred-score))
      (cl-incf weight-total 0.30))
    (if (> weight-total 0)
        (/ score weight-total)
      0.0)))
```

#### Step 4: Verify All Tests Pass

```bash
# Run full test suite
emacs --batch -l test-runner.el -l ert -f ert-run-tests-batch-and-exit
;; Expected: 1303 tests, 0 unexpected
```

### Weight Rebalancing

| Component | Old Weight | New Weight |
|-----------|------------|------------|
| Docstrings | 40% | 20% |
| Positive patterns | 0% | 30% |
| Length | 30% | 25% |
| Complexity | 30% | 25% |

### Result

Code with good patterns but no docstrings:
- **Before**: 0.51 (discarded)
- **After**: 0.70+ (retained)

---

## 5. Actionable Patterns Summary

### Code Agent Efficiency

- [ ] Define task scope before starting
- [ ] Budget 3-5 files for exploration, 1-2 for edits
- [ ] Monitor eight-keys metrics per task
- [ ] Skip unnecessary phases for simple tasks

### Surgical Editing

- [ ] Make minimal edits that preserve structure
- [ ] Edit boundaries first, content second
- [ ] Verify after each atomic change
- [ ] Use `check-parens` after nested edits

### Systematic Review

- [ ] Scan entire codebase before fixing
- [ ] Categorize issues: Critical → High → Medium → Low
- [ ] Fix incrementally, verify after each category
- [ ] Track metrics: issues found, fixed, remaining

### Test-Driven Development

- [ ] Write tests before implementation
- [ ] Run tests to confirm expected failures
- [ ] Implement minimally to pass tests
- [ ] Rebalance weights based on test results
- [ ] Verify with full test suite

---

## Related

- [[Testing Strategies]] - Comprehensive testing approaches
- [[Refactoring Patterns]] - Code transformation techniques
- [[Workflow Optimization]] - Task efficiency methods
- [[Code Quality Metrics]] - Measurement and improvement
- [[Debugging Techniques]] - Error identification and resolution

---

## References

- Wu Xing Constraints Framework (anti-pattern detection)
- Eight Keys Metrics System (efficiency measurement)
- Batch Analysis Methodology (systematic review)
- TDD Cycle Pattern (test-first development)
```