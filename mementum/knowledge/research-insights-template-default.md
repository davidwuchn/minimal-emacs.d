---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 0.4/10
allium-issues: 0
allium-severity: 0.00
allium-status: coherent
---

# Research Strategy: template-default

*Consolidated from 187 experiments (4% keep rate).*

**Performance:** 7 kept / 1 discarded / 10 failed (EXTRACTED — from TSV)

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

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.




## Allium Behavioral Spec (auto-generated, v3)

*0 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
## Distilled Findings

The research touched 24 target files across the gptel-auto-workflow and gptel-tools-agent modules (with three `staging-*` files), yielding 187 experiments but no kept hypothesis from the current round. The retained hypotheses all describe the same recurring pattern: **idempotency/symmetry gaps in lifecycle helpers, brittle `eq`-vs-`equal` cache invalidation, and missing nil/error guards around external state**.

### The single most important finding

A latent runtime crash exists in `gptel-benchmark-eight-keys-weakest`: `not-applicable` symbols flow into `<`-based sorting on scores, producing `(< 'not-applicable <number>)`. This is the only kept hypothesis tied to a hard bug rather than a structural improvement.

### Patterns worth acting on (in priority order)

1. **Idempotency / symmetry gap** — Adding advice without checking whether it is already installed leads to duplicate or stacked advice. The same area also lacks a paired disable function. (φ Vitality + fractal Clarity)
2. **Identity-based cache invalidation** — `gptel-auto-workflow--normalized-projects` uses `eq` on the project list, so any reassignment to a new list with equal contents invalidates the cache. Switching to `equal` and reordering the cache check ahead of `ensure-buffer-tables` is the canonical fix. (φ Vitality + fractal Clarity)
3. **Missing nil/empty guards on FSM and filesystem state** — Buffer lookups, `file-attributes` on potentially invalid paths, and empty project lists all need explicit guards. (Clarity + Vitality)
4. **UI-intent simplification** — `format-mode-line` can be replaced with direct `mode-name` access; `if` with single branch can be `when`. Low-impact clarity win. (Clarity)
5. **Misleading message + missing directory validation** — Pure bug-fix-class change.

### Discarded note

One experiment surfaced with no hypothesis stated; safe to ignore for downstream planning.

### Recommendation

Treat the `not-applicable` sorting crash as the must-fix item. The remaining four are a coherent refactor cluster — batching them as one "guard/symmetry/cache-correctness" pass will lift both φ Vitality and fractal Clarity metrics without touching the ontology/strategy modules that the research also exercised.
```

