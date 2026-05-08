---
title: Experiment Insights - gptel-ext-context-cache
status: active
category: knowledge
tags: [auto-workflow, experiments, gptel-ext-context-cache]
updated: 2026-05-08 10:15
---

# Experiment Insights: gptel-ext-context-cache

*Consolidated from e2e run 2026-05-08T021050Z-bf4d.*

**Keep rate:** 25% (1 kept / 4 total)

## Successful Improvements

- **Exp1 (KEPT, score 9/9):** Adding validation for non-positive-integer cached values in `my/gptel--cache-or-alist-lookup` and extracting fallback logic into a helper function fixes inconsistent caching behavior in the `t` branch, improves code clarity, and normalizes numeric values.

## Discarded Patterns

- **Exp2 (discarded):** Adding a sentinel for failed normalization attempts. Graded 4/4 but score tie without positive combined improvement. Sentinels add complexity without measurable benefit.
- **Exp3 (validation-failed):** Extracting duplicate normalize-then-validate pattern into a helper. Failed pre-grade validation: introduced undefined function `cw` (unavailable/Common Lisp symbol).
- **Exp4 (repeated-focus-symbol):** Storing a miss sentinel when normalization fails. Discarded: repeated focus on `my/gptel--cache-or-alist-lookup` after 2 prior non-kept attempts.

## Key Learnings

- **Refactoring + bug fix combos score highest:** Exp1 combined helper extraction with a real bug fix (caching in `t` branch), earning 9/9. Pure refactoring without bug fix (Exp2, Exp4) stalls.
- **Watch for unavailable runtime symbols:** `cw`, `file`, `plusp`, `getf`, `hash-table-contains-p` are Common Lisp functions not available in Emacs Lisp. Pre-grade validation catches these but costs an experiment.
- **Quality gain threshold matters:** Exp2 had score tie but quality 0.87 → 0.87 (no gain). The comparator rejected it. Need ≥0.01 quality gain on ties.

## What Does Not Work

- Sentinels for cache misses: adds indirection without improving the score.
- Pure DRY refactoring without a bug fix or performance improvement: graders see it as "style-only" even when functional.
