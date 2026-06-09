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

*3 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Distilled Research Output

## Strategy
**template-default** — 166 experiments across ~50 gptel/agent workflow modules.

## Signal-to-Noise
Overwhelmingly empty. Of 166 experiments, **1 substantive hypothesis was kept**; the rest were discarded as `unknown` or template placeholders (one discarded entry even left blank where "[what changes & why]" was required).

## The One Finding Worth Keeping

> **Wrap `gptel--fsm-next` in `condition-case` to prevent retry-machinery crashes.**
>
> In `my/gptel-auto-retry`, if the FSM is in an invalid state and cannot determine the next transition, `gptel--fsm-next` raises an error that propagates up and aborts the retry loop entirely. Wrapping the call in `condition-case` and falling back to `ERRS` lets the original transition path handle the failure gracefully instead of tearing down the retry pipeline.

### Concrete shape
```elisp
;; before
(next-state (gptel--fsm-next fsm current-state))

;; after  
(next-state (condition-case nil
                (gptel--fsm-next fsm current-state)
              (error 'errs)))
```

### Why it matters
- The retry path (`my/gptel-auto-retry`) is a recovery mechanism — it is *itself* the thing that should never crash on FSM invalidity.
- Falling back to `ERRS` preserves the existing error-handling transition rather than bypassing it via an uncaught throw.
- This is defensive coding for a rare but observable failure mode (stale FSM state after upstream errors).

## Honest Assessment

The 166-experiment run produced near-zero yield. Possible causes:
- **Template-default strategy too generic** — no target-specific hypothesis generation.
- **Targets too broad** — 47 modules means shallow coverage per module.
- **Hypothesis template not enforced** — discarded hypotheses are literally `unknown` or left blank, suggesting the experimental loop isn't producing candidates worth testing.

## Recommendation
Before another 166-experiment run, tighten:
1. **Scope** — pick 3–5 modules per cycle, not 47.
2. **Hypothesis template** — reject `unknown` results instead of recording them as "discarded".
3. **Strategy** — replace `template-default` with a per-module seed (recent diffs, open TODOs, error sites) so candidates are anchored to real code, not generic patterns.
```

### Check Issues

# Review

Overall this is **well-structured and honest** — the meta-observations about the 166-experiment run are the strongest part. But the single technical finding has issues worth fixing before it's acted on.

## Concrete issues

### 1. `ERRS` vs `'errs` — case and quoting mismatch
The prose refers to `ERRS` (uppercase) but the code returns `'errs` (lowercase, quoted symbol). In Emacs Lisp these are **different symbols**. Pick one and use it consistently. If the FSM actually defines a state called `errs` (lowercase), the code is correct and the prose needs fixing. If the prose was intended literally, the code needs fixing.

### 2. Symbol vs keyword — the fallback value
`(error 'errs)` returns the **symbol** `errs`. This only works if the FSM's error state is literally the symbol `errs`. If states are keywords (`:errs`), strings (`"errs"`), or something else, this silently does the wrong thing — `next-state` will be bound to a value the FSM can't match.

**Check the actual FSM definition** in `my/gptel-auto-retry`. If states are declared like `(defconst my/gptel-auto-retry-states '(ok errs retry done))`, the symbol is correct. If they're keywords, this is a bug.

### 3. Claims stated more definitively than the evidence supports
> "`gptel--fsm-next` raises an error that propagates up and aborts the retry loop entirely"

This reads as observed fact, but it's an **interpretation of behavior**. Was the propagation actually traced, or inferred from a crash trace? "Observed" or "r

... (truncated)
