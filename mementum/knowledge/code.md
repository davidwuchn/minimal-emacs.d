---
title: Code Development Patterns and Techniques
status: active
category: knowledge
tags: [workflow, code-agent, efficiency, tdd, review, editing]
---

# Code Development Patterns and Techniques

This knowledge page synthesizes patterns for efficient code development, from agent workflow optimization to systematic review strategies and surgical editing techniques.

---

## Code Agent Efficiency Patterns

Understanding how code agents perform across different task types enables better task design and workflow optimization.

### Task Type Efficiency Analysis

Based on benchmark analysis across 3 test cases:

| Task Type | Efficiency | Steps | Pattern |
|-----------|------------|-------|---------|
| Simple edit | 0.82-0.90 | 5-6 | read → edit (direct) |
| Exploration | 0.72 | 8 | glob → read×N → edit |

### Eight Keys Alignment Metrics

Track agent performance across vitality, clarity, and synthesis dimensions:

| Key | code-001 | code-002 | code-003 | Avg |
|-----|----------|----------|----------|-----|
| vitality | 0.85 | 0.88 | 0.78 | 0.84 |
| clarity | 0.82 | 0.90 | 0.72 | 0.81 |
| synthesis | 0.80 | 0.85 | 0.75 | 0.80 |

### Anti-Pattern Detection

All tests pass Wu Xing constraints:

- **wood-overgrowth**: ✓ (steps <= 20)
- **fire-excess**: ✓ (efficiency >= 0.5)
- **metal-rigidity**: ✓ (tool-score >= 0.6)
- **tool-misuse**: ✓ (steps <= 15, continuations <= 3)

### Improvement Strategies

**For Exploration Tasks (code-003):**
- Add exploration scope hints to task descriptions
- Use `--max-count` or `--max-depth` in glob/grep
- Budget: 3-5 files for exploration, 1-2 for targeted edits

**Phase Transition Pattern:**
- Simple edits can skip P2 and go P1 → P3 directly
- This is more efficient than full cycle for simple tasks

---

## Surgical Editing for Nested Code

When working with deeply nested code structures (10+ levels), precision editing prevents parentheses imbalance errors.

### The Problem

Large block replacements in nested structures often break due to mismatched parentheses:

```elisp
;; This often breaks due to missing/mismatched parens
(edit old-block new-block)
```

### The Solution: Minimal Edits

Make incremental changes rather than wholesale replacements:

```elisp
;; Step 1: Edit just the function call
(edit "gptel-auto-experiment-decide"
      "(let ((code-quality ...))
         (gptel-auto-experiment-decide")

;; Step 2: Edit just the closing parens
(edit "exp-result))))))))))))"
      "exp-result)))))))))))))")  ; one more paren for let
```

### Verification Commands

```bash
# Check file loads
emacs --batch -l file.el

# Check parentheses balance (will hang if unbalanced)
timeout 10 emacs --batch --eval "(progn (find-file ...) (while t (forward-sexp)))"
```

**Key Pattern:** λ surgical - minimal changes preserve structure

---

## Systematic Code Review Strategy

Batch analysis across entire repos is more effective than single-file optimization.

### The Approach

1. **Scan entire codebase** with batch tools:
   - `emacs --batch -f batch-byte-compile` for warnings/errors
   - `grep` for duplicate definitions
   - Count issues by category

2. **Categorize by severity**:

   | Severity | Issue Type | Example |
   |----------|------------|---------|
   | Critical | Duplicate functions | Same defun name twice |
   | High | Unused/free variables | Referenced undefined symbol |
   | Medium | Docstring width | Line > 80 chars |
   | Low | Missing declare-function | Undefined function reference |

3. **Fix in order**: Critical → High → Medium → Low

4. **Verify incrementally**: Run byte-compile after each category

### Practical Commands

```bash
# Find all warnings
emacs --batch --eval "(setq byte-compile-error-on-warn nil)" \
  -f batch-byte-compile lisp/modules/*.el 2>&1 | grep Warning

# Find duplicate functions
grep -rh "(defun " lisp/ | sed 's/(defun \([^ ]*\).*/\1/' | \
  sort | uniq -c | sort -rn | head

# Find docstring width issues
emacs --batch -f batch-byte-compile *.el 2>&1 | \
  grep "docstring wider than 80"
```

### Results

- Found 5 categories of issues
- Fixed 22 total issues across 6 files
- Reduced warnings from ~20 to 1 (false positive)

**Key Insight:** Broad exploration → categorize → prioritize → fix systematically is more effective than narrow focus.

---

## TDD Approach for Code Quality Metric

Test-driven development ensures metrics capture intended behavior before implementation.

### The Problem

Old metric weighted docstrings at 40%, penalizing generated code without docs. Code scoring 0.83 could drop to 0.51 after changes, triggering discard even when eight-keys score was high.

### TDD Implementation

**Step 1: Write tests first**
Created 6 new tests in test-grader-subagent.el:
- `gptel-benchmark--positive-patterns-score` function existence
- Error handling rewards
- Bad naming penalties
- Type predicate rewards
- Weight distribution verification
- Minimum score threshold (≥0.70 for good patterns without docs)

**Step 2: Run tests to see failures**
All 6 tests failed as expected

**Step 3: Implement solution**
Added `gptel-benchmark--positive-patterns-score` function scoring:
- Error handling (40%): condition-case, user-error, error, signal
- Naming conventions (30%): penalizes my-, foo-, bar- prefixes
- Standard predicates (30%): null, stringp, listp, etc.

**Step 4: Rebalance weights**
- Docstrings: 20% (was 40%)
- Positive patterns: 30% (new)
- Length: 25%
- Complexity: 25%

**Step 5: Verify**
All tests pass (1303 tests, 0 unexpected)

### Result

Code with good patterns but no docstrings now scores ≥0.70 instead of 0.51. Valid experiments with error handling and type checking won't be discarded.

**Key Pattern:** TDD cycle: test → fail → implement → pass. Tests encode requirements before code exists.

---

## Actionable Patterns Summary

| Pattern | When to Use | Command/Tool |
|---------|-------------|--------------|
| Direct path (P1→P3) | Simple edit tasks | Skip exploration phase |
| Scope hints | Exploration tasks | --max-count, --max-depth |
| Minimal edits | Nested code | Edit boundaries incrementally |
| Batch analysis | Code review | emacs --batch -f batch-byte-compile |
| Severity ordering | Fix prioritization | Critical → High → Medium → Low |
| TDD | Metric/function development | test → fail → implement → pass |

---

## Related

- [Workflow Optimization] - Eight Keys alignment and efficiency metrics
- [Code Quality Metrics] - Weight balancing and threshold tuning
- [Testing Patterns] - Test-driven development practices
- [Emacs Configuration] - Batch compilation and verification

---

*Synthesized: 2026-03-24*
*Category: knowledge*
*Tags: workflow, code-agent, efficiency, tdd, review, editing, benchmark*