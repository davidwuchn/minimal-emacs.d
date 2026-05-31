---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 0.5/10
allium-issues: 3
allium-severity: 0.00
allium-status: ok
---

# Research Strategy: template-default

*Consolidated from 42 experiments (5% keep rate).*

**Performance:** 2 kept / 0 discarded / 25 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-auto-workflow-projects.el` (2 kept / 3 failed)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-auto-workflow--ensure-buffer-tables, gptel-auto-workflow--normalized-projects, gptel-auto-workflow--normalize-worktree-dir, gptel-auto-workflow--buffer-tool-snapshot, gptel-auto-workflow--routed-fsm-info, gptel-auto-workflow--get-worktree-buffer, gptel-auto-workflow--get-project-buffer, gptel-auto-workflow-add-project, gptel-auto-workflow-remove-project, gptel-auto-workflow-list-projects, gptel-auto-workflow-run-all-projects, gptel-auto-workflow--finish-queued-cron-job, gptel-auto-workflow--queue-cron-job, gptel-auto-workflow-queue-all-projects, gptel-auto-workflow--get-project-for-context, gptel-auto-workflow--advice-task-override, gptel-auto-workflow-enable-per-project-subagents, gptel-auto-workflow-disable-per-project-subagents, gptel-auto-workflow--advice-task-overlay-buffer, gptel-auto-workflow--enable-overlay-buffer-advice
defvars: gptel-auto-workflow--async, gptel-auto-workflow--process, gptel-auto-workflow--worktree-state, gptel-auto-workflow-worktree-base, gptel-auto-workflow--current-target, gptel-auto-workflow-projects, gptel-auto-workflow--project-buffers, gptel-auto-workflow--current-project, gptel-auto-workflow--run-project-root, gptel-auto-workflow--cron-job-running, gptel-auto-workflow--stats, gptel-auto-workflow--running, gptel-auto-workflow--cron-job-timer, gptel-auto-workflow--defer-subagent-env-persistence, mementum-root, gptel-auto-workflow--project-root-override), gptel-auto-workflow--research-findings-cache, gptel-auto-workflow--worktree-buffers, gptel-auto-workflow--normalized-projects-cache, gptel-auto-workflow--normalized-projects-hash
requires: cl-lib, gptel-tools-agent
provides: gptel-auto-workflow-projects
declares: gptel-auto-workflow--project-root, gptel-auto-workflow--get-worktree-dir, gptel-auto-workflow--mark-messages-start, gptel-auto-workflow--persist-status, gptel-auto-workflow-cron-safe, gptel-auto-workflow-run-async--guarded, gptel-auto-workflow-run-research, gptel-fsm-info, gptel-mementum-weekly-job, gptel-benchmark-instincts-weekly-job, gptel-auto-workflow--run-autotts-evolution, gptel-auto-workflow--reorder-fallbacks-by-ontology, gptel-auto-workflow--run-research-champion-league, gptel-auto-workflow--run-strategy-evolution
errors: error, error, error, error, error, error, error, user-error, error, error, error, error, error, signal
handlers: err, err, err, err, nil, nil, err, err, nil, nil, err, err, err, err, err, err, err
advised: gptel-agent--task, gptel-agent--task-overlay
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-auto-workflow-projects.el` (2 kept / 3 failed)
- `lisp/modules/gptel-benchmark-subagent.el` (3 failed)
- `lisp/modules/gptel-tools-agent-error.el` (3 failed)
- `lisp/modules/gptel-tools-agent-prompt-build.el` (3 failed)
- `lisp/modules/gptel-auto-workflow-strategic.el` (3 failed)

## Allium Behavioral Coherence

*3 behavioral issues (severity 0.00). EXTRACTED from Allium v3 pipeline.*



## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.
















































## Allium Behavioral Spec (auto-generated, v3)

*4 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Research Strategy Distillation

## Overview
- **Template**: template-default
- **Scope**: 65 experiments across 10 targets

## Key Hypotheses (Kept)

1. **Cache Validation** — Replace `eq` with `equal` for project list comparison; check cache before `ensure-buffer-tables`. Improves Vitality (adapts to usage) and Clarity (explicit content-based invalidation).

2. **Buffer Lookup Extraction** — Extract buffer lookup into clear validation sequence with explicit nil guards. Improves Clarity (visible assumptions) and Vitality (graceful FSM handling).

3. **Adaptive Error Recovery** — Add `ignore-errors` around `file-attributes` and early guard for empty projects. Improves Vitality (edge case handling) and Clarity (explicit validity assumptions).

4. **Mode-Line Simplification** — Replace `format-mode-line` with direct `mode-name` access; use `when` vs `if`. Improves Clarity (reduces complexity).

5. **Benchmark Crash Prevention** — Filter `not-applicable` entries before sorting in `gptel-benchmark-eight-keys-weakest`. Improves both Clarity (explicit filtering) and Vitality (fixes latent bug).

## Additional Changes

- Idempotency guard for re-adding advice + symmetric disable function
- Bug fix: misleading message + directory existence validation

## Discarded

- (None explicitly listed in provided text)
```

### Check Issues

# Review: Research Strategy Distillation

## Overall Assessment

**Rating: 7/10** — Solid foundational document with good structure, but several areas need clarification.

---

## Strengths

| Aspect | Notes |
|--------|-------|
| **Structure** | Clean separation of kept/discarded changes |
| **Scope definition** | Explicit experiment count (65) and target count (10) |
| **Hypothesis format** | Each has clear "Improves X and Y" rationale |
| **Categorization** | Distinguishes key hypotheses from additional changes |

---

## Issues & Questions

### 1. Missing Context
- What are the **targets** being experimented on?
- What does "template-default" mean in this context?

### 2. Vague Descriptions
- **Hypothesis 4** ("Mode-Line Simplification"): `format-mode-line` vs direct access is a performance vs correctness tradeoff—clarify which problem this solves
- **Additional Changes**: "Bug fix: misleading message" — what was the message?

### 3. Inconsistent Formatting
- "Kept" uses numbered list; "Additional Changes" uses bullet points
- "Discarded" section is empty but still present

### 4. Missing Validation Criteria
- How will you measure if these hypotheses hold?
- No success metrics defined

---

## Recommendations

1. **Add experiment mapping** — Which hypotheses map to which targets/experiments?
2. **Define "distillation" criteria** — What determined kept vs discarded?
3. **Add risk assessment** — What's the impact if a hypothesis fails?
4. **Complete the Discarded section** — Either remove it or add N/A

... (truncated)
