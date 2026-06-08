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

*0 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Distillation

## Scope
- **Strategy:** template-default
- **Experiments:** 67 across 9 targets
- **Files investigated:** 8 gptel modules + 1 staging-review

## Valid Findings (2 kept, 0 discarded)

### 1. Dead-marker crash risk via `where` parameter
**Issue:** A `where` value may be a marker from a buffer that has since been killed. Passing such a dead marker downstream will trigger errors.
**Fix:** Add a `marker-live` check before delegating `where` to the original function.

### 2. Missing nil-guard in `gptel-auto-workflow--research-cache-get`
**Issue:** The function assumes the research-findings cache hash table is live. If nil (early startup or after error recovery), it raises `wrong-type-argument`.
**Fix:** Add a `hash-table-p` guard, mirroring the existing pattern in `gptel-auto-workflow-strategic.el:2719-2721`.
**Note:** This is an internal inconsistency — the same library already protects against this case elsewhere.

## Net Assessment
Both findings are **defensive-coding gaps** in early/error-recovery paths. Neither appears to be a logic bug; both are robustness/consistency fixes. Low risk to apply, high value for startup and post-error resilience.
```

### Check Issues

# Review of Distillation

## What's working

- **Clean separation** of findings from net assessment — easy to scan.
- **Finding 2 is well-anchored:** names the function, points to the reference pattern with line numbers, and the "internal inconsistency" note is the strongest part — it's a load-bearing argument that the fix is *removing* inconsistency, not adding new behavior.
- **Net assessment correctly distinguishes** defensive-coding gaps from logic bugs, and the risk/value framing ("low risk to apply, high value") is appropriate.

## What needs attention

### 1. Asymmetric specificity between the two findings
Finding 2 cites a function name and a reference line range (`gptel-auto-workflow-strategic.el:2719-2721`). Finding 1 cites neither. It should specify:
- Which function receives `where`
- Which downstream call would raise (e.g., `save-excursion`, `goto-char`, `insert`?)
- File and approximate line range

Without that, Finding 1 is unverifiable from the document alone.

### 2. "0 discarded" is underspecified
"2 kept, 0 discarded" implies a triage step, but the original count is missing. Readers can't judge the filter's selectivity. Either drop the kept/discarded framing or include the input count (e.g., "2 kept, 0 discarded from N total").

### 3. "template-default" strategy is undefined
In Scope, this label is opaque. If it refers to a specific strategy in the codebase, name it; if it's a meta-template descriptor, say so explicitly. As written, a reader six months from now w

... (truncated)
