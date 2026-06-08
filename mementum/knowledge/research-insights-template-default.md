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

*Consolidated from 67 experiments (3% keep rate).*

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

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.
















## Allium Behavioral Spec (auto-generated, v3)

*5 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
## Distillation

**Signal-to-noise: very low.** 159 experiments fired but only 1 hypothesis survived with a concrete mechanism; the rest collapsed to `unknown`. The template is under-specified — the "[what changes & why]" sentinel leaked into the discarded bucket, meaning the framework couldn't distinguish "no result" from "no change."

### What was actually learned

1. **`gptel--fsm-next` is a crash surface.** Wrapping it in `condition-case` and falling through to `ERRS` is a valid hardening pattern for `my/gptel-auto-retry` when the FSM lands in an unrecoverable state. Cheap, local, low-risk.

2. **The discarded set is the real story.** Dozens of hypotheses across the workflow/agent/extension modules (cache, staging-merge, circuit-breaker, ontology-router, code-regeneration, etc.) produced no usable signal. That's not a negative result per experiment — it's the strategy failing to discriminate. Probable causes:
   - Hypotheses too vague to refute (the template's "[what changes & why]" blank is diagnostic)
   - Targets too coarse-grained (module-level rather than function-level)
   - No baseline comparison anchored

### Recommended next move

Before re-running 159 experiments, fix the template: force every hypothesis to name (a) the specific function/symbol touched, (b) the observable change, and (c) the failure mode it prevents. The single surviving hypothesis has all three; the discarded ones don't.

Want me to redesign the hypothesis template, or rerun against the surviving FSM finding to validate it under load?
```

### Check Issues

# Check

**Overall:** Sound diagnosis, well-hedged, clean handoff. The meta-finding (the strategy couldn't discriminate) is correctly identified as more important than the single surviving hypothesis. A few things to tighten or push back on:

## What works

- **The epistemic frame is right.** "Not a negative result per experiment — it's the strategy failing to discriminate" is the most important line in the whole document. It correctly separates *evidence of absence* from *absence of evidence*. Don't bury this.
- **The FSM finding is concrete enough to act on.** Function name, failure mode, mitigation idiom. That's actionable. Worth validating.
- **The binary close is good.** "Redesign template OR validate survivor" forces a decision instead of another 159-experiment muddle.

## What's weak or missing

1. **No breakdown of the 158 discarded.** You say they collapsed to `unknown` and that the cause is "probable" — but which cause, and in what proportion? A quick triage (e.g., "120 lacked an observable, 30 lacked a function, 8 lacked both") would tell you whether the template fix is sufficient or whether the target granularity is also broken. Right now the diagnosis is plausible but unfalsifiable.

2. **The template critique is slightly under-stated.** A sentinel that *leaks into the discarded bucket* isn't under-specification — it's a missing required field. That's a design bug, not a soft prompt issue. Worth saying outright: the template doesn't enforce its own structure.

3. 

... (truncated)
