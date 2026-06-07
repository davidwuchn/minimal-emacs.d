---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 0.3/10
allium-issues: 0
allium-severity: 0.00
allium-status: coherent
---

# Research Strategy: template-default

*Consolidated from 217 experiments (3% keep rate).*

**Performance:** 7 kept / 1 discarded / 12 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-auto-workflow-projects.el` (6 kept / 2 failed)
- `lisp/modules/gptel-benchmark-principles.el` (1 kept / 6 failed)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-auto-workflow--ensure-buffer-tables, gptel-auto-workflow--normalized-projects, gptel-auto-workflow--normalize-worktree-dir, gptel-auto-workflow--buffer-tool-snapshot, gptel-auto-workflow--routed-fsm-info, gptel-auto-workflow--get-worktree-buffer, gptel-auto-workflow--get-project-buffer, gptel-auto-workflow-add-project, gptel-auto-workflow-remove-project, gptel-auto-workflow-list-projects, gptel-auto-workflow-run-all-projects, gptel-auto-workflow--finish-queued-cron-job, gptel-auto-workflow--queue-cron-job, gptel-auto-workflow-queue-all-projects, gptel-auto-workflow--get-project-for-context, gptel-auto-workflow--advice-task-override, gptel-auto-workflow-enable-per-project-subagents, gptel-auto-workflow-disable-per-project-subagents, gptel-auto-workflow--advice-task-overlay-buffer, gptel-auto-workflow--enable-overlay-buffer-advice
defvars: gptel-auto-workflow--async, gptel-auto-workflow--process, gptel-auto-workflow--worktree-state, gptel-auto-workflow-worktree-base, gptel-auto-workflow--current-target, gptel-auto-experiment--quota-exhausted, gptel-auto-workflow--run-id, gptel-auto-workflow--status-run-id, gptel-auto-workflow-persistent-headless, gptel-auto-workflow-projects, gptel-auto-workflow--project-buffers, gptel-auto-workflow--current-project, gptel-auto-workflow--run-project-root, gptel-auto-workflow--cron-job-running, gptel-auto-workflow--stats, gptel-auto-workflow--running, gptel-auto-workflow--cron-job-timer, gptel-auto-workflow--defer-subagent-env-persistence, mementum-root, gptel-auto-workflow--project-root-override)
requires: cl-lib, gptel-tools-agent
provides: gptel-auto-workflow-projects
declares: gptel-auto-workflow--project-root, gptel-auto-workflow--get-worktree-dir, gptel-auto-workflow--mark-messages-start, gptel-auto-workflow--persist-status, gptel-auto-workflow-cron-safe, gptel-auto-workflow-run-async--guarded, gptel-auto-workflow-run-research, gptel-fsm-info, gptel-mementum-weekly-job, gptel-benchmark-instincts-weekly-job, gptel-auto-workflow--run-autotts-evolution, gptel-auto-workflow--reorder-fallbacks-by-ontology, gptel-auto-workflow--run-research-champion-league, gptel-auto-workflow--run-strategy-evolution, gptel-auto-workflow--worktree-base-root, gptel-auto-workflow--make-idempotent-callback, gptel-agent--update-agents, my/gptel-agent--task-override
errors: error, error, error, error, error, error, error, user-error, error, error, error, error, error, error, error, signal
handlers: err, err, err, err, nil, nil, err, err, err, nil, nil, err, err, err, err, err, err, err
advised: gptel-agent--task, gptel-agent--task-overlay
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings
were misleading.

- `lisp/modules/gptel-auto-workflow-strategic.el` (1 failed)
- `lisp/modules/gptel-auto-workflow-projects.el` (6 kept / 2 failed)
- `lisp/modules/gptel-benchmark-principles.el` (1 kept / 6 failed)
- `lisp/modules/gptel-auto-workflow-mementum.el` (1 failed)
- `lisp/modules/gptel-auto-workflow-production-metrics.el` (1 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.








## Allium Behavioral Spec (auto-generated, v3)

*0 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Distilled Hypotheses

All kept hypotheses target two principles: **φ Vitality** (progressive improvement, adaptive to discovery/edge cases) and **fractal Clarity** (explicit assumptions, testable, minimal complexity).

## By Theme

### 1. Cache & State Management
- **Cache identity vs. content**: `gptel-auto-workflow--normalized-projects` uses `eq` for project-list comparison, causing spurious invalidation when `gptel-auto-workflow-projects` is rebound to an equal list. Switch to `equal` and check cache before `ensure-buffer-tables`.
- **Buffer lookup hardening**: Extract buffer lookup into a validation sequence with explicit nil guards, so the function tolerates missing FSM state.

### 2. Error Handling & Edge Cases
- **Path validation**: Add directory existence check and correct a misleading error message.
- **Project-list edge cases**: Wrap `file-attributes` in `ignore-errors` and early-return on an empty project list.

### 3. Idempotency / Lifecycle
- **Advice re-activation guard**: Prevent re-adding advice that's already active, and extract the symmetric disable function.

### 4. Simplification (Clarity)
- Replace `format-mode-line` with direct `mode-name`; swap `if` for `when`; add a nil-safety guard around buffer iteration.

### 5. Latent Bug Fix
- `gptel-benchmark-eight-keys-weakest` crashes when scoring task-type hypotheses because `not-applicable` symbols break `(< 'not-applicable <number>)` during sort. Filter `not-applicable` entries before sorting.

## Common Pattern

Every hypothesis is a **small, surgical change** to existing code (not a refactor), explicitly justified against the dual metrics of Vitality + Clarity. Several overlap thematically (defensive guards, explicit assumptions, content-based comparisons) and could be batched.

## Discarded

None — the discarded section is empty ("No hypothesis stated").
```

### Check Issues

# Review: Distilled Hypotheses

Overall, this is a clean, well-structured triage document. The thematic grouping is sensible, each hypothesis is actionable, and the "common pattern" observation is a useful meta-synthesis. A few things worth flagging:

## Strengths

- **Actionability**: Every hypothesis states both *what* to change and *why* — good for review and execution.
- **Thematic clustering** is real, not forced: the guard/early-return pattern genuinely recurs across sections 2, 3, and 4.
- **The "Common Pattern" section** correctly notices that several items could be batched — this is a useful planning signal.

## Concerns & Gaps

### 1. The "Discarded" section being empty is a yellow flag
If no candidate hypotheses were considered and dropped, either (a) the upstream set was already pre-filtered (in which case say so), or (b) the distillation process isn't being surfaced honestly. A brief note like "all candidates survived the φ/Clarity filter" would close the loop.

### 2. Mix of diagnosis and prescription
Several entries conflate "what is wrong" with "how to fix it." For example:
- §1: *"causing spurious invalidation when … is rebound to an equal list"* — this is a diagnosis.
- *"Switch to `equal` and check cache before `ensure-buffer-tables`"* — this is a prescription.

Splitting these would let reviewers challenge one without the other. Also, `equal` on a list of project structures may be more expensive than `eq` on a stable list — worth justifying the cost vs. the alt

... (truncated)
