---
title: Experiment Insights - gptel-tools-agent-strategy-evolver
status: active
category: knowledge
tags: [auto-workflow, experiments, gptel-tools-agent-strategy-evolver]
---

# Experiment Insights: gptel-tools-agent-strategy-evolver

*Consolidated from e2e run 2026-05-08T021050Z-bf4d.*

**Keep rate:** 33% (2 kept / 6 total)

## Successful Improvements

- **Exp2 (KEPT, score 9/9):** Adding early validation for nil/empty response in `gptel-auto-workflow--parse-strategy-candidates` prevents runtime crashes when gptel request fails or returns invalid data, improving Vitality (error resilience).
- **Exp3 (KEPT, score 4/4):** Extracting duplicate nil/empty validation into a helper function `gptel-auto-workflow--valid-code-string-p` and adding nil guards to 6 functions improves Clarity (explicit assumptions) and Vitality (error resilience).

## Discarded Patterns

- **Exp1 (staging-flow-failed):** Adding nil guards to four string-processing functions. Graded 4/4 but staging flow failed during merge. Likely a transient issue.
- **Exp4 (discarded):** Extracting duplicate code-block extraction into two helper functions. Graded 9/9 but combined score regressed (0.57 → 0.56). Quality improvement (0.78 → 0.79) wasn't enough.
- **Exp5 (repeated-focus-symbol):** Refactoring extraction functions to use `gptel-auto-workflow--extract-matches`. Discarded: repeated focus on `gptel-auto-workflow--parse-strategy-candidates` after 2 prior non-kept attempts.
- **Exp6 (validation-retry-failed):** Extracting nested validation logic into a helper using `catch`/`throw`. Pre-grade validation failed; retry timed out after 240s.

## Key Learnings

- **Vitality + Clarity combo is the sweet spot for this target:** Both kept experiments improved error resilience (Vitality) and explicit assumptions (Clarity).
- **Nil guards on string-processing functions score well but need careful staging:** Exp1 graded perfectly but failed during staging merge. Verify staging flow separately.
- **Helper extraction works when it consolidates ≥4 call sites:** Exp3's helper replaced validation logic across 6 functions. Exp4's helpers only affected 1 function and didn't justify the indirection.
- **Avoid `catch`/`throw` for validation:** Exp6 introduced non-local exits that complicate control flow and fail validation. Use `when`/`unless` guards instead.

## What Does Not Work

- Refactoring a single function with helpers: no score improvement, grader sees as unnecessary indirection.
- Revisiting `parse-strategy-candidates` after 2 non-kept attempts: the repeated-focus-symbol filter blocks this correctly.
- Complex control-flow refactoring (`catch`/`throw`): fails pre-grade validation and retry times out.

## Patterns to Reuse

```elisp
;; Validated pattern: nil guard + early return
(unless (and code (stringp code))
  (error "..."))

;; Validated pattern: extract validation into helper
(defun gptel-auto-workflow--valid-code-string-p (code)
  "Validate CODE is a non-empty string."
  (and code (stringp code) (> (length code) 0)))
```
