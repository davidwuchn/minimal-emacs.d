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

*Consolidated from 188 experiments (4% keep rate).*

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

*2 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
The user wants me to distill the research strategy findings. They've provided:

1. A research strategy: template-default
2. 139 experiments across various targets (lisp modules and staging configs)
3. Kept hypotheses: 2 hypotheses about Emacs Lisp code
4. Discarded hypotheses: (none listed)

The task seems to be to distill this information into a concise summary. Let me analyze what's being asked.

Looking at the structure, this appears to be a research experiment log where:
- They ran 139 experiments across various Emacs Lisp modules
- They kept 2 specific hypotheses
- They discarded 0 (or the discarded ones aren't shown)

The two kept hypotheses are:
1. Add marker-live check for the `where` parameter in some function
2. Add `hash-table-p` guard in `gptel-auto-workflow--research-cache-get` for nil-safety

I should distill this into a clear, useful summary. The user likely wants me to:
- Summarize what was found
- Identify the key patterns/insights
- Present this concisely

Let me think about what "distill" means here - it means to extract the essential meaning from. So I should condense this large research output into the key findings.

Key observations:
1. The research used a "template-default" strategy
2. 139 experiments were run across many related Emacs Lisp modules dealing with workflow, agents, and tools
3. Only 2 hypotheses were kept (very selective)
4. The kept hypotheses share a common theme: defensive programming / nil-safety / guard conditions
5. Both are about preventing crashes from edge cases (dead markers, nil hash tables)

The pattern is interesting: both kept hypotheses are about robust error handling, specifically:
- Guarding against invalid input states (dead markers)
- Guarding against nil/uninitialized data structures (nil hash tables)

This suggests the research was looking for code robustness issues.

Let me write a distilled summary.
```

### Check Issues

# Distilled Research Summary

**Strategy:** template-default  
**Volume:** 139 experiments across Emacs Lisp modules (`gptel`, workflow, agent, tool)  
**Yield:** 2 kept hypotheses, 0 discarded

## Kept Hypotheses

1. **`marker-live` guard on `where` parameter** — in some function accepting a marker, validate it's still live before using it (prevents crash from dead/garbage-collected markers).

2. **`hash-table-p` guard in `gptel-auto-workflow--research-cache-get`** — verify the argument is actually a hash table before calling hash-table accessors (prevents error when the cache slot is nil or holds the wrong type).

## Key Pattern

Both surviving hypotheses are **defensive nil/type guards** — hardening against edge cases where a parameter is present but in an invalid state (dead marker, nil/non-hash-table). Neither addresses logic, performance, or feature gaps; the signal the research surfaced is purely about **crash-resistance at boundary points**.

## Interpretation

- The template-default strategy produced a high volume of false positives — only 2 of 139 (~1.4%) survived.
- Surviving findings cluster tightly: same defensive-programming motif, same class of bug (external/edge-case input shape, not core algorithm).
- No hypotheses about behavior, semantics, or correctness-of-result were retained — suggesting either (a) such hypotheses weren't generated, or (b) they were all discarded upstream and aren't shown here.

## Caveat

With **zero discarded hypotheses listed**, the rejection 

... (truncated)
