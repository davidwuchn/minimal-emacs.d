---
name: evolution-patterns
description: Domain knowledge for experiment hypothesis categorization and score prediction. Extracted from gptel-auto-workflow-evolution.el.
version: 1.0
evolve-script: evolve_patterns.py
metadata:
  evolution-stats:
    total-experiments: 870
    last-evolution: 2026-05-08 20:01

---
# Evolution Patterns

## Hypothesis Categories

Hypotheses are categorized by keyword matching (order matters - first match wins):

### Safety (Highest Priority)
**Keywords:** safety, defensive, type.*check, assert, sanitize, escape, validate, secure, audit, harden

**Examples:**
- Adding validation for nil input
- Type checking function arguments
- Security audit of user input

### Bug Fix
**Keywords:** bug, fix, nil, error, runtime, crash, prevent, guard, off-by-one, boundary, threshold, inaccurate, safeguard, protect, check.*nil, null, missing.*check

**Examples:**
- Fixing off-by-one error in loop
- Adding null pointer guard
- Correcting inaccurate calculation

### Performance
**Keywords:** performance, cache, optimize, speed, slow, complexity, hot path, efficient, reduce.*time, faster, memory, allocation, gc

**Examples:**
- Adding cache for expensive computation
- Reducing time complexity
- Optimizing memory allocation

### Refactoring
**Keywords:** extract, duplicate, dedup, refactor, helper, rename, organiz, cleanup, consolidat, centraliz, reus, maintainability, clarity

**Examples:**
- Extracting duplicate logic into helper
- Renaming unclear functions
- Centralizing repeated patterns

### Other (Default)
Catch-all for hypotheses that don't match above categories.

## Score Predictor

Based on historical experiment data:

| Pattern | Predicts | Confidence |
|---------|----------|------------|
| Validation guard (proper-list-p, nil check) | KEEP | High |
| Bug fix + refactor combo | KEEP | High |
| Extract helper alone | DISCARD | Medium |
| catch/throw or complex flow | DISCARD | High |
| Common Lisp symbols (cw, file, plusp) | VALIDATION-FAILED | Very High |
| >50 lines changed | TIMEOUT/DISCARD | Medium |

## Success Patterns (What Works)

- Targeted changes to single functions
- Clear functional impact (not just style)
- Validation guards or bug fixes with measurable improvement

## Failure Patterns (What to Avoid)

- Score tie without quality gain (need ≥0.01 improvement)
- Pure refactoring without bug fix (grader sees as style-only)
- Introducing undefined functions (Common Lisp symbols in Emacs Lisp)
- Complex control flow (catch/throw, non-local exits)
- Repeated focus on same function after 2+ non-kept attempts

## Usage

```elisp
;; Categorize a hypothesis
(gptel-auto-workflow--categorize-hypothesis "Add nil check to process-item")
;; Returns: 'bug-fix

;; Check prediction for a pattern
(gptel-auto-workflow--pattern-predicts "validation guard" 'keep)
;; Returns: 'high
```

## Evolution Notes

- Update keyword lists based on new hypothesis types
- Refine confidence scores as more experiments accumulate
- Add new anti-patterns discovered during experiments
- Consider adding target-specific patterns


## Evolved Error Patterns

Based on analysis of experiment errors.

| Pattern | Category | Action | Frequency | Regex |
|---------|----------|--------|-----------|-------|

## Evolved Patterns

Updated: 2026-05-10 10:42

### High-Signal Keywords

- `inputs`: 75% (6/8)
- ``state``: 67% (4/6)
- `pairs)`: 60% (3/5)
- `circular`: 60% (3/5)
- `loading`: 60% (3/5)
- `avoiding`: 57% (4/7)
- ``listp``: 53% (10/19)
- `corrupted`: 50% (3/6)
- `assumptions).`: 50% (3/6)
- ``gptel-auto-workflow--filter-large-files``: 50% (3/6)
- `defensive`: 49% (18/37)
- `score`: 45% (5/11)
- `become`: 43% (3/7)
- ``resp``: 43% (3/7)
- `nil-guard`: 43% (3/7)
- ``stringp``: 43% (3/7)
- `sandbox`: 43% (3/7)
- `inputs.`: 43% (3/7)
- `(explicit`: 42% (11/26)
- `task`: 42% (5/12)