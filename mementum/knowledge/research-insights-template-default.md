---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 0.2/10
allium-issues: 3
allium-severity: 0.05
allium-status: ok
---

# Research Strategy: template-default

*Consolidated from 99 experiments (2% keep rate).*

**Performance:** 2 kept / 0 discarded / 42 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-auto-workflow-projects.el` (2 kept / 4 failed)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-auto-workflow--ensure-buffer-tables, gptel-auto-workflow--normalized-projects, gptel-auto-workflow--normalize-worktree-dir, gptel-auto-workflow--buffer-tool-snapshot, gptel-auto-workflow--routed-fsm-info, gptel-auto-workflow--get-worktree-buffer, gptel-auto-workflow--get-project-buffer, gptel-auto-workflow-add-project, gptel-auto-workflow-remove-project, gptel-auto-workflow-list-projects, gptel-auto-workflow-run-all-projects, gptel-auto-workflow--finish-queued-cron-job, gptel-auto-workflow--queue-cron-job, gptel-auto-workflow-queue-all-projects, gptel-auto-workflow--get-project-for-context, gptel-auto-workflow--advice-task-override, gptel-auto-workflow-enable-per-project-subagents, gptel-auto-workflow-disable-per-project-subagents, gptel-auto-workflow--advice-task-overlay-buffer, gptel-auto-workflow--enable-overlay-buffer-advice
defvars: gptel-auto-workflow--async, gptel-auto-workflow--process, gptel-auto-workflow--worktree-state, gptel-auto-workflow-worktree-base, gptel-auto-workflow--current-target, gptel-auto-workflow-projects, gptel-auto-workflow--project-buffers, gptel-auto-workflow--current-project, gptel-auto-workflow--run-project-root, gptel-auto-workflow--cron-job-running, gptel-auto-workflow--stats, gptel-auto-workflow--running, gptel-auto-workflow--cron-job-timer, gptel-auto-workflow--defer-subagent-env-persistence, mementum-root, gptel-auto-workflow--project-root-override), gptel-auto-workflow--research-findings-cache, gptel-auto-workflow--worktree-buffers, gptel-auto-workflow--normalized-projects-cache, gptel-auto-workflow--normalized-projects-hash
requires: cl-lib, gptel-tools-agent
provides: gptel-auto-workflow-projects
declares: gptel-auto-workflow--project-root, gptel-auto-workflow--get-worktree-dir, gptel-auto-workflow--mark-messages-start, gptel-auto-workflow--persist-status, gptel-auto-workflow-cron-safe, gptel-auto-workflow-run-async--guarded, gptel-auto-workflow-run-research, gptel-fsm-info, gptel-mementum-weekly-job, gptel-benchmark-instincts-weekly-job, gptel-auto-workflow--run-autotts-evolution, gptel-auto-workflow--reorder-fallbacks-by-ontology, gptel-auto-workflow--run-research-champion-league, gptel-auto-workflow--run-strategy-evolution
errors: error, error, error, error, error, error, error, user-error, error, error, error, error, error, error, signal
handlers: err, err, err, err, nil, nil, err, err, err, nil, nil, err, err, err, err, err, err, err
advised: gptel-agent--task, gptel-agent--task-overlay
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-auto-workflow-projects.el` (2 kept / 4 failed)
- `lisp/modules/gptel-benchmark-subagent.el` (3 failed)
- `lisp/modules/gptel-tools-agent-error.el` (3 failed)
- `lisp/modules/gptel-tools-agent-prompt-build.el` (3 failed)
- `lisp/modules/gptel-auto-workflow-strategic.el` (10 failed)

## Allium Behavioral Coherence

*3 behavioral issues (severity 0.05). EXTRACTED from Allium v3 pipeline.*



## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.


























































































## Allium Behavioral Spec (auto-generated, v3)

*0 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Distillation

## Scope
99 experiments across 12 targets in the gptel/auto-workflow codebase, using a template-default research strategy.

## Distilled Hypotheses (2 kept, 0 discarded)

Both surviving hypotheses target **defensive nil/lifecycle safety** in Emacs Lisp functions, suggesting a pattern of crashes or `wrong-type-argument` errors occurring during startup or post-error recovery states.

### H1: Dead-marker handling for `where` parameter
- **Defect class:** Stale/lifecycle argument validation
- **Fix shape:** Wrap `where` usage with `marker-live` (or equivalent) check before passing to the underlying function
- **Failure mode avoided:** Passing a marker from a killed buffer to the original function

### H2: Nil-safety in research cache accessor
- **Target:** `gptel-auto-workflow--research-cache-get`
- **Defect class:** Missing nil/hash-table guard
- **Fix shape:** Prepend `hash-table-p` check before table operations
- **Failure mode avoided:** `wrong-type-argument` error when the research findings cache is nil
- **Internal precedent:** `strategic.el` (lines 2719–2721) already implements this pattern — H2 closes a consistency gap

## Pattern Signal
Both kept hypotheses point at the same root concern: **input/state validation in helper functions during fragile lifecycle windows** (early startup, post-error recovery). No other defect classes (logic, performance, API misuse, etc.) survived the 99-experiment filter — strongly suggesting the actual bug surface is narrow and lifecycle-bound.

## Discarded
None recorded.
```

### Check Issues

I can't access the filesystem to verify the specific code claims (the `strategic.el` precedent, the function `gptel-auto-workflow--research-cache-get`, or the `where` parameter usage). So here's a check based on the document's own internal consistency and the framing.

## Issues worth flagging

**1. "Discarded: None recorded" is suspicious given 99 experiments.**
99 experiments across 12 targets with only 2 survivors and zero rejections is an unusual result. Either:
- The filter is too permissive (keeping weak hypotheses), or
- The filter is too narrow (only looking for one defect class and discarding misclassified-but-valid ones elsewhere), or
- "None recorded" means the logging was skipped, which is itself a process bug.

This claim deserves scrutiny before acting on it.

**2. The `strategic.el` precedent claim is the load-bearing piece of evidence and it's unverifiable from the distillation alone.**
H2's strength rests entirely on "lines 2719–2721 already implement this pattern." If that precedent is:
- A coincidental `hash-table-p` check in an unrelated function, H2 is weaker
- A `null`/empty-table check that doesn't actually fix the same failure mode, the "consistency gap" framing is wrong
- Misread (e.g., the check guards a different code path), H2 collapses

**3. The pattern signal overgeneralizes from n=2.**
"Both kept hypotheses point at the same root concern" — yes, trivially, when the filter kept only ones that did. From two survivors you cannot claim "the actual bug s

... (truncated)
