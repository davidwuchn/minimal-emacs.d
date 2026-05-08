---
title: Experiment Insights - gptel-sandbox
status: active
category: knowledge
tags: [auto-workflow, experiments, gptel-sandbox]
updated: 2026-05-08 10:15
---

# Experiment Insights: gptel-sandbox

*Consolidated from e2e run 2026-05-08T021050Z-bf4d.*

**Keep rate:** 25% (1 kept / 4 total)

## Successful Improvements

- **Exp1 (KEPT, score 4/4):** Adding `proper-list-p` validation for state parameter in `gptel-sandbox--run-forms` prevents silent failures when improper lists are passed, improving Clarity by making explicit assumptions testable.

## Discarded Patterns

- **Repeated focus on `gptel-sandbox--execute-tool`:** Two experiments (Exp2, Exp3) proposed the same `listp` → `proper-list-p` change in different functions. Both discarded: no score improvement.
- **Repeated focus on `gptel-sandbox--run-forms`:** Exp4 attempted to extract duplicate plist-get operations into a helper. Discarded due to repeated-focus-symbol after 2 prior non-kept attempts on this function.

## Key Learnings

- **Safety axis is productive for this target** (46% success rate): validation guards score well.
- **Avoid focusing on the same function after 2 non-kept attempts** — the repeated-focus-symbol filter correctly prevents stagnation.
- **Validation changes need functional impact:** `proper-list-p` vs `listp` is a real behavior difference (catches dotted pairs, circular lists) and graders reward this.

## What Does Not Work

- Extracting duplicate plist-get into helpers: no score improvement, seen as refactor without clear bug fix.
- Adding the same validation to multiple functions sequentially: grader scores each independently; if the first didn't improve the score, subsequent ones won't either.
