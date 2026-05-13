---
name: evolution-patterns
description: Domain knowledge for experiment hypothesis categorization and score prediction. Extracted from gptel-auto-workflow-evolution.el.
version: 1.0
evolve-script: evolve_patterns.py
metadata:
  evolution-stats:
    total-experiments: 870

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

### High-Signal Keywords

- `(adapts`: 100% (9/9)
- `several`: 100% (6/6)
- `pre-existing`: 100% (6/6)
- ``id``: 100% (5/5)
- `reporting`: 100% (5/5)
- `cases.let`: 100% (5/5)
- `about`: 84% (16/19)
- ``my/gptel--sanitize-multimodal-content``: 83% (5/6)
- `gptel-ext-core.el`: 83% (5/6)
- ``fsm``: 83% (5/6)
- `invariant`: 83% (5/6)
- `change.`: 83% (5/6)
- `malformed,`: 83% (5/6)
- `score`: 81% (13/16)
- `definitions)`: 80% (16/20)
- `analyze`: 80% (4/5)
- ``gptel-benchmark-analyze-patterns``: 80% (4/5)
- ``gptel-benchmark-summarize-results``: 80% (4/5)
- ``gptel-benchmark--accumulate-scores``: 80% (4/5)
- `detection.`: 80% (4/5)
