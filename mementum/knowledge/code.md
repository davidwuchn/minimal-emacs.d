---
title: Code Quality and Efficiency Patterns
status: active
category: knowledge
tags: [code, efficiency, workflow, tdd, review, refactoring]
---

# Code Quality and Efficiency Patterns

This knowledge page synthesizes patterns for code agent efficiency, surgical editing, systematic review, and test-driven development. These patterns collectively improve code quality metrics and workflow productivity.

## Code Agent Efficiency Patterns

Analysis of code agent performance reveals significant variation by task type. Understanding these patterns enables better task design and workflow optimization.

### Efficiency by Task Type

| Task Type | Efficiency | Steps | Pattern |
|-----------|------------|-------|---------|
| Simple edit | 0.82-0.90 | 5-6 | read → edit (direct) |
| Exploration | 0.72 | 8 | glob → read×N → edit |

**Key Insight:** Simple edits benefit from direct paths (P1 → P3), skipping intermediate phases. Exploration tasks require more context management.

### Eight Keys Alignment Metrics

The eight keys framework provides measurable dimensions for code quality:

| Key | code-001 | code-002 | code-003 | Average |
|-----|----------|----------|----------|---------|
| vitality | 0.85 | 0.88 | 0.78 | 0.84 |
| clarity | 0.82 | 0.90 | 0.72 | 0.81 |
| synthesis | 0.80 | 0.85 | 0.75 | 0.80 |

**Actionable Pattern:** Aim for vitality ≥ 0.85, clarity ≥ 0.80, synthesis ≥ 0.80 for good code quality.

### Anti-Pattern Detection

Wu Xing constraints provide automated anti-pattern detection:

| Anti-Pattern | Check | Threshold |
|--------------|-------|-----------|
| wood-overgrowth | steps ≤ 20 | ✓ Pass |
| fire-excess | efficiency ≥ 0.5 | ✓ Pass |
| metal-rigidity | tool-score ≥ 0.6 | ✓ Pass |
| tool-misuse | steps ≤ 15, continuations ≤ 3 | ✓ Pass |

### Improvement Strategies

**For Exploration Tasks (lowest efficiency: 0.72):**

1. Add scope hints to task descriptions
2. Use `--max-count` or `--max-depth` in glob/grep:
   ```bash
   # Limit glob results to 5 files
   find . -name "*.el" -maxdepth 3 | head -5
   grep -l "pattern" --include="*.el" | head -5
   ```
3. Budget: 3-5 files for exploration, 1-2 for targeted edits
4. Avoid 2+ continuations by setting explicit scope upfront

**For Phase Transitions:**
- Simple edits: Direct path (P1 → P3) is valid and more efficient
- Complex tasks: Full cycle ensures thoroughness

---

## Surgical Edits for Nested Code

When modifying deeply nested code (10+ levels), preserving structural integrity requires minimal, sequential edits.

### The Problem

Large block replacements in nested structures often break parentheses balance:
```elisp
;; This often breaks due to missing/mismatched parens
(edit old-block new-block)
```

### The Solution: Minimal Sequential Edits

**Step 1: Edit the function call first**
```elisp
(edit "gptel-auto-experiment-decide"
      "(let ((code-quality ...))
         (gptel-auto-experiment-decide")
```

**Step 2: Edit the closing parens last**
```elisp
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

**Pattern Symbol:** λ surgical - minimal changes preserve structure

---

## Systematic Code Review Strategy

Batch analysis across the entire codebase is more effective than single-file optimization.

### The Approach

1. **Scan entire codebase** with batch tools
2. **Categorize by severity** (Critical → High → Medium → Low)
3. **Fix in order** of severity
4. **Verify incrementally** after each category

### Severity Categories

| Severity | Issues | Examples | Action |
|----------|--------|----------|--------|
| Critical | Runtime errors | Duplicate function definitions | Immediate fix |
| High | Logic errors | Unused variables, free variables | Priority fix |
| Medium | Style issues | Docstring width > 80, wrong quotes | Batch fix |
| Low | Missing declarations | Missing declare-function | Optional fix |

### Diagnostic Commands

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

### Results Pattern

| Phase | Issues Found | Fixes Applied | Warnings After |
|-------|--------------|---------------|----------------|
| Initial scan | ~20 | - | ~20 |
| After Critical | 5 | 5 | ~15 |
| After High | 10 | 8 | ~5 |
| After Medium | 5 | 2 | ~1 |
| After Low | 2 | 1 | 0 |

**Key Insight:** Broad exploration → categorize → prioritize → fix systematically is more effective than narrow focus.

---

## TDD Approach for Code Quality Metrics

Test-driven development improves code quality metrics by encoding requirements before implementation.

### The Problem

Old metric weighted docstrings at 40%, penalizing generated code without documentation:
- Code scoring 0.83 before changes could drop to 0.51 after
- Valid experiments with high eight-keys scores were being discarded

### The TDD Cycle

```
┌─────────────────────────────────────┐
│  1. Write tests (encode requirements) │
└─────────────────┬───────────────────┘
                  ▼
┌─────────────────────────────────────┐
│  2. Run tests (see failures)        │
└─────────────────┬───────────────────┘
                  ▼
┌─────────────────────────────────────┐
│  3. Implement (satisfy tests)        │
└─────────────────┬───────────────────┘
                  ▼
┌─────────────────────────────────────┐
│  4. Verify (all tests pass)         │
└─────────────────────────────────────┘
```

### Implementation Example

**Step 1: Write 6 tests in test-grader-subagent.el**
```elisp
(ert-deftest test-positive-patterns-score-existence ()
  "Test that gptel-benchmark--positive-patterns-score exists"
  (should (fboundp 'gptel-benchmark--positive-patterns-score)))

(ert-deftest test-positive-patterns-rewards-error-handling ()
  "Test that error handling is rewarded"
  (should (> (gptel-benchmark--positive-patterns-score "(condition-case ...)") 0))

(ert-deftest test-positive-patterns-penalizes-bad-naming ()
  "Test that my-, foo-, bar- prefixes are penalized"
  (should (< (gptel-benchmark--positive-patterns-score "my-var") 0.5))

(ert-deftest test-positive-patterns-rewards-type-predicates ()
  "Test that type predicates are rewarded"
  (should (> (gptel-benchmark--positive-patterns-score "(stringp x)") 0))

(ert-deftest test-positive-patterns-weight-distribution ()
  "Test weights sum to 1.0"
  (should (= (+ docstring-weight positive-weight length-weight complexity-weight) 1.0)))

(ert-deftest test-positive-patterns-minimum-score-threshold ()
  "Test good patterns without docs score >= 0.70"
  (should (>= (gptel-benchmark--positive-patterns-score "(condition-case err (progn (stringp x)))") 0.70)))
```

**Step 2: Run tests → All 6 fail (expected)**

**Step 3: Implement the function**
```elisp
(defun gptel-benchmark--positive-patterns-score (code)
  "Score CODE based on positive patterns.
Returns weighted sum of error handling (40%), naming (30%), and type predicates (30%)."
  (let ((error-score (if (or (string-match "condition-case" code)
                             (string-match "user-error" code)
                             (string-match "(error " code)
                             (string-match "(signal " code))
                        1.0 0.0))
        (naming-score (if (or (string-match "my-" code)
                              (string-match "foo-" code)
                              (string-match "bar-" code))
                         0.0 1.0))
        (predicate-score (if (or (string-match "(null " code)
                                  (string-match "(stringp " code)
                                  (string-match "(listp " code)
                                  (string-match "(numberp " code))
                            1.0 0.0)))
    (+ (* error-score 0.4)
       (* naming-score 0.3)
       (* predicate-score 0.3))))
```

**Step 4: Rebalance weights**
| Component | Old Weight | New Weight |
|-----------|------------|------------|
| Docstrings | 40% | 20% |
| Positive Patterns | 0% | 30% |
| Length | 25% | 25% |
| Complexity | 35% | 25% |

**Result:** Code with good patterns but no docs now scores ≥0.70 (was 0.51).

---

## Actionable Patterns Summary

### Task Design
1. Add scope hints for exploration tasks (prevents 2+ continuations)
2. Budget 3-5 files for exploration, 1-2 for edits
3. Use direct paths (P1→P3) for simple edits

### Editing
1. Make minimal, sequential edits to nested code
2. Edit beginning first, then end
3. Verify after each edit with `emacs --batch -l`

### Review
1. Scan entire codebase before fixing
2. Categorize issues by severity
3. Fix Critical → High → Medium → Low
4. Verify incrementally after each category

### Testing
1. Write tests before implementation
2. Encode requirements as assertions
3. Rebalance weights to avoid discarding valid work

---

## Related

- [[Eight Keys Framework]] - Vitality, clarity, synthesis metrics
- [[Wu Xing Constraints]] - Anti-pattern detection
- [[Emacs Batch Tools]] - batch-byte-compile, batch-byte-compile
- [[Code Quality Metrics]] - Weight distribution, scoring functions
- [[Refactoring Patterns]] - Surgical edits, incremental changes

---

*Synthesized from memories: 2026-03-22, 2026-03-24*