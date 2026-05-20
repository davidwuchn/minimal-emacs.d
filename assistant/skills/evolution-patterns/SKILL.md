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


## Current Performance

- Keep rate when this skill is used: {{skill-keep-rate}}
- Experiments using this skill: {{skill-experiments}}
- Overall system keep rate: {{overall-keep-rate}}
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
