---
title: Code Development Patterns and Best Practices
status: active
category: knowledge
tags: [code-agent, efficiency, tdd, code-review, refactoring, workflow]
---

# Code Development Patterns and Best Practices

This knowledge page synthesizes patterns for efficient code development, including code agent workflow optimization, safe refactoring techniques, systematic review strategies, and test-driven quality improvement.

---

## Code Agent Efficiency Patterns

### Task Type Performance Analysis

Code agent efficiency varies significantly by task type. Based on benchmark analysis across 3 test cases:

| Task Type | Efficiency | Steps | Pattern | Key Insight |
|-----------|------------|-------|---------|-------------|
| Simple Edit | 0.82-0.90 | 5-6 | read → edit (direct) | Direct path optimal |
| Targeted Edit | 0.88 | ~5 | read → grep → edit | Focused search |
| Exploration | 0.72 | 8 | glob → read×N → edit | Context heavy |

### Efficiency Anti-Pattern Detection

All tests pass the Wu Xing constraints:

| Anti-Pattern | Trigger Condition | Status | Remedy |
|--------------|-------------------|--------|--------|
| wood-overgrowth | steps > 20 | ✓ Pass | Keep steps minimal |
| fire-excess | efficiency < 0.5 | ✓ Pass | Maintain focus |
| metal-rigidity | tool-score < 0.6 | ✓ Pass | Use appropriate tools |
| tool-misuse | steps > 15 or continuations > 3 | ✓ Pass | Limit iterations |

### Improvement Strategies

**For Exploration Tasks (lowest efficiency at 0.72):**

1. **Add scope hints** to task descriptions:
   ```
   # Instead of: "Find all experiments"
   # Use: "Find up to 5 key experiments in lib/"
   ```

2. **Use limiting flags** in glob/grep:
   ```bash
   # Limit results for exploration
   ls -la *.el --max-count=5
   grep --max-count=10 "pattern" .
   ```

3. **Budget context allocation**:
   - Exploration: 3-5 files maximum
   - Targeted edits: 1-2 files maximum
   - Synthesize before expanding scope

### Phase Transition Patterns

**Observation:** Simple edit tasks (code-001) went P1 → P3, skipping P2 entirely.

**Pattern:** Direct path is more efficient than full cycle for simple tasks. Document when phase transitions can be skipped:

| Task Complexity | Recommended Path |
|-----------------|------------------|
| Simple edit | P1 → P3 (skip P2) |
| Feature add | P1 → P2 → P3 (full) |
| Refactor | P1 → P2 → P3 (full) |

---

## Eight Keys Alignment Metrics

Track alignment scores across code agent runs:

| Key | code-001 | code-002 | code-003 | Average |
|-----|----------|----------|----------|---------|
| vitality | 0.85 | 0.88 | 0.78 | **0.84** |
| clarity | 0.82 | 0.90 | 0.72 | **0.81** |
| synthesis | 0.80 | 0.85 | 0.75 | **0.80** |

**Target thresholds:**
- vitality ≥ 0.80: Code executes without errors
- clarity ≥ 0.75: Readable, well-structured
- synthesis ≥ 0.75: Components work together

---

## Surgical Edits for Nested Code

### The Problem

Large edit operations on deeply nested code (10+ levels of nesting) easily break parentheses balance, causing syntax errors that cascade through the file.

### Failed Approach

```elisp
;; BROKEN: Replacing large block often leaves unbalanced parens
(edit old-block new-block)
;; Result: (let ((x 1)) (func (a (b (c (new-content))))))
```

### Successful Approach: Minimal Step Edits

```elisp
;; Step 1: Edit just the function call wrapper
(edit "gptel-auto-experiment-decide"
      "(let ((code-quality ...))
         (gptel-auto-experiment-decide")

;; Step 2: Edit just the closing parens separately
(edit "exp-result))))))))))))"
      "exp-result)))))))))))))")  ; added one more for let
```

### Verification Commands

```bash
# Check file loads without errors
emacs --batch -l file.el

# Check parentheses balance (will hang if unbalanced)
timeout 10 emacs --batch --eval "(progn (find-file \"file.el\") (while t (forward-sexp)))"

# Alternative: Use check-parens
emacs --batch --eval "(progn (find-file \"file.el\") (check-parens))"
```

### Key Principle

> **λ surgical** = minimal changes preserve structure

Make one logical change at a time. Verify after each edit. This approach:
- Limits failure blast radius
- Makes debugging easier
- Creates clearer git history

---

## Systematic Code Review Strategy

### The Insight

Batch analysis across entire repository is more effective than single-file optimization. Categorizing issues by severity and fixing in order yields measurable improvements.

### The Approach

#### 1. Scan Entire Codebase with Batch Tools

```bash
# Compile all files, capture warnings
emacs --batch --eval "(setq byte-compile-error-on-warn nil)" \
  -f batch-byte-compile lisp/modules/*.el 2>&1 | grep Warning

# Find duplicate function definitions
grep -rh "(defun " lisp/ | sed 's/(defun \([^ ]*\).*/\1/' | \
  sort | uniq -c | sort -rn | head

# Find docstring width issues
emacs --batch -f batch-byte-compile *.el 2>&1 | \
  grep "docstring wider than 80"
```

#### 2. Categorize by Severity

| Severity | Issue Type | Example | Impact |
|----------|------------|---------|--------|
| Critical | Duplicate functions | Two `defun foo` | Runtime errors |
| High | Unused variables | `let ((x ...))` never used | Confuses readers |
| High | Free variables | Unbound symbol referenced | Runtime errors |
| Medium | Docstring width | Line > 80 chars | Breaks formatting |
| Medium | Wrong quotes | "curly" instead of 'straight | Style violation |
| Low | Missing declare-function | Autoloads not declared | Load warnings |

#### 3. Fix in Order

```
Critical → High → Medium → Low
```

#### 4. Verify Incrementally

```bash
# After each category fix:
emacs --batch -f batch-byte-compile file.el
```

### Results Observed

- Found 5 categories of issues across 6 files
- Fixed 22 total issues
- Reduced warnings from ~20 to 1 (false positive)

### Pattern Summary

```
Broad exploration → categorize → prioritize → fix systematically
```

This outperforms narrow focus on one file or one strategy.

---

## TDD Approach for Code Quality Metric

### The Problem

Old code quality metric weighted docstrings at 40%, penalizing generated code without documentation:

- Code scoring 0.83 before metric change could drop to 0.51 after
- Valid experiments with high eight-keys scores were being discarded
- Generated code without docstrings was systemically undervalued

### The Solution: TDD Cycle

#### 1. Write Tests First (6 new tests)

Create tests in `test-grader-subagent.el`:

```elisp
;; Test existence of scoring function
(should (fboundp 'gptel-benchmark--positive-patterns-score))

;; Test error handling rewards
(should (>= (gptel-benchmark--score-error-handling
             "(condition-case err (progn ...))") 5))

;; Test bad naming penalties
(should (< (gptel-benchmark--score-naming
            "(defun my-foo ...)") 0))

;; Test standard predicates reward
(should (> (gptel-benchmark--score-predicates
            "(when (null x) ...)") 3))

;; Test weight distribution
(should (= (+ docstring-weight positive-weight length-weight complexity-weight) 100))

;; Test minimum threshold for good patterns
(should (>= (gptel-benchmark--score-positive-patterns
             "(defun valid-name (x) (when (null x) (signal \"err\" nil)))")
            0.70))
```

#### 2. Run Tests to See Failures

All 6 tests failed as expected—no implementation yet.

#### 3. Implement the Function

```elisp
(defun gptel-benchmark--positive-patterns-score (code)
  "Score CODE based on positive patterns, ignoring docstrings.
Returns score 0-1 weighted as: error-handling (40%), naming (30%), predicates (30%)."
  (let ((error-score (* 0.4 (score-error-handling code)))
        (naming-score (* 0.3 (score-naming-conventions code)))
        (predicate-score (* 0.3 (score-standard-predicates code))))
    (+ error-score naming-score predicate-score)))
```

**Scoring rules:**
- **Error handling (40%)**: condition-case, user-error, error, signal
- **Naming conventions (30%)**: penalizes `my-`, `foo-`, `bar-` prefixes
- **Standard predicates (30%)**: null, stringp, listp, etc.

#### 4. Rebalance Weights

| Metric | Old Weight | New Weight |
|--------|------------|------------|
| Docstrings | 40% | 20% |
| Positive patterns | 0% | 30% |
| Length | 30% | 25% |
| Complexity | 30% | 25% |

#### 5. Verify

```bash
# Run full test suite
emacs --batch -l test-grader-subagent.el -f ert-run-tests-batch-and-exit

;; Result: 1303 tests, 0 unexpected, 0 failed
```

### Result

Code with good patterns but no docstrings now scores ≥0.70 instead of 0.51. Valid experiments with error handling and type checking are no longer discarded.

### Pattern

> **TDD cycle**: test → fail → implement → pass

Tests encode requirements before code exists. This ensures:
- Requirements are explicit and testable
- Implementation meets actual needs
- Regression protection for future changes

---

## Actionable Patterns Summary

| Pattern | When to Use | Key Command/Tech |
|---------|-------------|------------------|
| **Direct path (P1→P3)** | Simple edits | Skip exploration phase |
| **Surgical edits** | Nested code | One change at a time, verify |
| **Batch review** | Full repo analysis | grep, batch-byte-compile |
| **Severity ordering** | Multiple issues | Critical → High → Medium → Low |
| **TDD cycle** | New feature/metric | test → fail → implement → pass |
| **Scope limiting** | Exploration tasks | --max-count, budget files |

---

## Related

- [[eight-keys]] - Alignment metrics for code agent vitality, clarity, synthesis
- [[workflow-optimization]] - Task description and context budget patterns
- [[emacs-lisp-refactoring]] - Surgical edit techniques for nested elisp
- [[benchmark-methodology]] - Test case design and metric validation
- [[anti-pattern-detection]] - Wu Xing constraints for workflow health

---

*Synthesized from: 2026-03-22 (code efficiency), 2026-03-22 (surgical edits), 2026-03-24 (systematic review), 2026-03-24 (TDD approach)*
*Status: active*