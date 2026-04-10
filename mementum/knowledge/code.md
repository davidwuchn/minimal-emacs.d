---
title: code
status: open
---

Synthesized from 4 memories.

# Code Agent Efficiency Patterns

> Discovered: 2026-03-22
> Category: benchmark
> Tags: workflow, code-agent, efficiency, eight-keys

## Summary

Code agent efficiency varies significantly by task type. Analysis of 3 test cases shows:

| Task Type | Efficiency | Steps | Pattern |
|-----------|------------|-------|---------|
| Simple edit | 0.82-0.90 | 5-6 | read → edit (direct) |
| Exploration | 0.72 | 8 | glob → read×N → edit |

## Anti-Pattern Detection

No anti-patterns triggered (all tests pass Wu Xing constraints):

- wood-overgrowth: ✓ (steps <= 20)
- fire-excess: ✓ (efficiency >= 0.5)
- metal-rigidity: ✓ (tool-score >= 0.6)
- tool-misuse: ✓ (steps <= 15, continuations <= 3)

## Improvement Opportunities

### 1. Exploration Tasks (code-003)

**Issue:** 2 continuations indicate context management needed.

**Remedy (Fire → Water):**
- Add exploration scope hints to task descriptions
- Use `--max-count` or `--max-depth` in glob/grep
- Budget: 3-5 files for exploration, 1-2 for targeted edits

### 2. Phase Transitions

**Observation:** code-001 went P1 → P3 (skipped P2), which is valid for simple edits.

**Pattern:** Direct path is more efficient than full cycle for simple tasks.

## Eight Keys Alignment

| Key | code-001 | code-002 | code-003 | Avg |
|-----|----------|----------|----------|-----|
| vitality | 0.85 | 0.88 | 0.78 | 0.84 |
| clarity | 0.82 | 0.90 | 0.72 | 0.81 |
| purpose | - | - | - | - |
| wisdom | - | - | - | - |
| synthesis | 0.80 | 0.85 | 0.75 | 0.80 |

## Recommendations

1. **Task Descriptions:** Add scope hints for exploration tasks
2. **Context Budget:** Limit exploration to 5 files before synthesis
3. **Phase Guidance:** Document when P2 can be skipped

---

λ explore(optimization). efficiency ∝ task_clarity + scope_definition

# Surgical Edits for Nested Code

## Problem

Large edit operations on deeply nested code (like the experiment workflow with 10+ levels of nesting) can easily break parentheses balance.

## Failed Approach

Replacing a large block with a new block:
```elisp
;; This often breaks due to missing/mismatched parens
(edit old-block new-block)
```

## Successful Approach

1. Make minimal edits - only change what needs changing
2. Edit the beginning first, then the end
3. Verify after each edit

```elisp
;; Step 1: Edit just the function call
(edit "gptel-auto-experiment-decide"
      "(let ((code-quality ...))
         (gptel-auto-experiment-decide")

;; Step 2: Edit just the closing parens
(edit "exp-result))))))))))))"
      "exp-result)))))))))))))")  ; one more paren for let
```

## Verification

```bash
# Check file loads
emacs --batch -l file.el

# Check parentheses balance (may hang if balanced)
timeout 10 emacs --batch --eval "(progn (find-file ...) (while t (forward-sexp)))"
```

## Symbol

λ surgical - minimal changes preserve structure

# Systematic Code Review Strategy

## Discovery
Batch analysis across entire repo is more effective than single-file optimization. Categorizing issues by severity and fixing in order yields measurable improvements.

## Approach
1. **Scan entire codebase** with batch tools:
   - `emacs --batch -f batch-byte-compile` for warnings/errors
   - `grep` for duplicate definitions
   - Count issues by category

2. **Categorize by severity**:
   - Critical: duplicate functions (runtime errors)
   - High: unused variables, free variables
   - Medium: docstring width, wrong quotes
   - Low: missing declare-function

3. **Fix in order**: Critical → High → Medium → Low

4. **Verify incrementally**: Run byte-compile after each category

## Tools Used
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

## Results
- Found 5 categories of issues
- Fixed 22 total issues across 6 files
- Reduced warnings from ~20 to 1 (false positive)

## Key Insight
Broad exploration → categorize → prioritize → fix systematically is more effective than narrow focus on one file or one strategy.

---
*Learned: 2026-03-24*

# TDD Approach for Code Quality Metric

## Insight
Used TDD to improve code quality metric that was discarding valid experiments.

## Problem
Old metric weighted docstrings at 40%, penalizing generated code without docs. Code scoring 0.83 before could drop to 0.51 after changes, triggering discard even when eight-keys score was high.

## Solution
1. **Write tests first**: Created 6 new tests in test-grader-subagent.el for:
   - `gptel-benchmark--positive-patterns-score` function existence
   - Error handling rewards
   - Bad naming penalties
   - Type predicate rewards
   - Weight distribution verification
   - Minimum score threshold (≥0.70 for good patterns without docs)

2. **Run tests to see failures**: All 6 tests failed as expected

3. **Implement**: Added `gptel-benchmark--positive-patterns-score` function scoring:
   - Error handling (40%): condition-case, user-error, error, signal
   - Naming conventions (30%): penalizes my-, foo-, bar- prefixes
   - Standard predicates (30%): null, stringp, listp, etc.

4. **Rebalance weights**: Docstrings 20% → Positive 30% → Length 25% → Complexity 25%

5. **Verify**: All tests pass (1303 tests, 0 unexpected)

## Result
Code with good patterns but no docstrings now scores ≥0.70 instead of 0.51. Valid experiments with error handling and type checking won't be discarded.

## Pattern
TDD cycle: test → fail → implement → pass. Tests encode requirements before code exists.