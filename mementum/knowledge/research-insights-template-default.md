---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 0.1/10
insight-quality: 0.6/10
allium-issues: 3
allium-severity: 0.00
allium-status: ok
---

# Research Strategy: template-default

*Consolidated from 105 experiments (1% keep rate).*

**Performance:** 1 kept / 1 discarded / 12 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-auto-workflow-projects.el` (1 kept / 5 failed)
*Consolidated from 34 experiments (6% keep rate).*

**Performance:** 2 kept / 0 discarded / 17 failed (EXTRACTED — from TSV)

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

- `lisp/modules/gptel-ext-context.el` (1 failed)
- `lisp/modules/gptel-auto-workflow-research-integration.el` (1 discarded / 1 failed)
- `lisp/modules/gptel-auto-workflow-strategic.el` (4 failed)
- `lisp/modules/gptel-auto-workflow-projects.el` (1 kept / 5 failed)
- `lisp/modules/gptel-tools-agent-error.el` (1 failed)
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

*2 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
**Distilled Research Strategy Update:**

**Scope:** 105 experiments executed across 14 targets (Lisp modules: `gptel-auto-workflow-*`, `gptel-benchmark-*`, `gptel-tools-*`, `gptel-ext-*`; scopes: `staging-scope`, `staging-review`, `test`).

**Outcome:**
*   **Kept:** Refinement of `gptel-auto-workflow-list-project-buffers` remains a viable hypothesis.
*   **Discarded:** Adding `(listp class)` guard in `gptel-auto-workflow--ontology-research-gaps` was rejected.


















































## Allium Behavioral Spec (auto-generated, v3)

*3 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
## Research Strategy: Distilled

**Template**: template-default  
**Scope**: 34 experiments across 8 target files

### Target Files
- `gptel-tools-agent-benchmark.el`
- `gptel-benchmark-subagent.el`
- `gptel-tools-agent-error.el`
- `gptel-tools-agent-prompt-build.el`
- `gptel-auto-workflow-strategic.el`
- `gptel-auto-workflow-projects.el`
- `gptel-auto-workflow-ontology-strategy.el`
- `gptel-tools-agent-experiment-core.el`

### Kept Hypotheses

1. **Marker-live check for `where` parameter** — Handle gracefully if `where` is a marker from a killed buffer, avoiding dead marker errors.

2. **Add `hash-table-p` guard in `gptel-auto-workflow--research-cache-get`** — Prevent `wrong-type-argument` errors when cache is nil. The pattern exists in `strategic.el` (line 2719-2721) but is missing here, creating an inconsistency that could crash during early startup or error recovery.

### Discarded Hypotheses

None.
```

### Check Issues

# Research Strategy Review

## Summary Assessment

The distilled strategy presents **2 focused hypotheses** across **8 target files** with **34 experiments**. This is a high ratio of experiments to hypotheses—may indicate fine-grained test cases or potential overlap.

---

## Hypothesis Validation

### ✅ Hypothesis 1: Marker-live check for `where`

**Valid concern.** Dead markers cause `marker-is-dead` errors.  
**Typical fix pattern:**

```elisp
(when (and (markerp where) (marker-buffer where))
  ;; safe to use marker
  )
```

**Verify:** Search for all call sites of `where` parameter across target files.

---

### ✅ Hypothesis 2: `hash-table-p` guard in `research-cache-get`

**Valid defensive coding.** Referencing `strategic.el` line 2719-2721 shows consistent pattern exists elsewhere.  
**Typical fix:**

```elisp
(when (hash-table-p cache)
  (gethash key cache))
```

**Verify:** 
- Confirm pattern is actually at line ~2719 in `strategic.el`
- Check if other files in scope have same missing guard

---

## Concerns

| Issue | Detail |
|-------|--------|
| **34 experiments** | High count for 2 hypotheses—may be over-partitioned |
| **Discarded: None** | Unusual—typically some hypotheses get filtered |
| **No priority** | Which experiments are critical path vs. nice-to-have? |

---

## Recommendations

1. **Collapse experiments** — 34 experiments for 2 hypotheses suggests each hypothesis has ~17 variants. Consider reducing to 6-10 focused tests.

2. **Document discarded hypotheses** — A "None" entry looks like an 

... (truncated)
