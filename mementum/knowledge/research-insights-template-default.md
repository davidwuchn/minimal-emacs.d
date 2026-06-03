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

*Consolidated from 61 experiments (3% keep rate).*

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
# Distillation

## Strategy
**Template-default** — systematic exploration across 8 gptel module files (61 experiments total).

## Validated Hypotheses (2 kept)

### H1: Dead-marker safety in `where` parameter
- **Issue:** `where` can be a marker from a killed buffer; passing it downstream risks passing a dead marker to the original function.
- **Fix:** Add a `marker-live` check before use.
- **Status:** Reasonable, localized defensive guard.

### H2: Nil-safety for research-cache getter
- **Issue:** `gptel-auto-workflow--research-cache-get` lacks a `hash-table-p` guard, so it can raise `wrong-type-argument` when the cache is `nil` (early startup, post-error recovery).
- **Fix:** Add `hash-table-p` guard, matching the existing pattern in `gptel-auto-workflow-strategic.el` (lines 2719–2721).
- **Status:** Inconsistency with sibling module; low-risk alignment fix.

## Discarded
*(none retained / section empty)*

## Net Takeaway
Two narrow, defensive-coding fixes — both about hardening against `nil`/dead values in cache-and-marker plumbing across the auto-workflow modules. No structural or behavioral changes proposed.
```

### Check Issues

## Check of Distillation

### What's solid

- **Both hypotheses describe well-known Emacs Lisp defensive idioms.** `marker-live` guarding a marker before downstream use, and `hash-table-p` guarding a cache before `gethash`/`puthash` are textbook. Both fixes are minimal and local.
- **H2's reasoning is good practice** — pointing to a sibling pattern in a named file with line numbers is exactly the kind of consistency-based argument that reviewers accept.
- **The Net Takeaway is consistent with the body** — two narrow guards, both about `nil`/dead-value handling, no behavioral change claimed.
- **Structure is clean.** Issue / Fix / Status per hypothesis is a good template; Status phrases give the reviewer an at-a-glance verdict.

### Needs verification against the source

1. **H2's line reference (2719–2721 of `gptel-auto-workflow-strategic.el`).** This is a load-bearing claim — the entire justification rests on the sibling file containing the pattern. If those three lines are not a `hash-table-p` guard on a similar getter, H2 needs a different framing.
2. **H1's call chain.** "Passing it downstream risks passing a dead marker to the original function" depends on (a) the buffer holding `where` actually being killable in the relevant code path, and (b) the *original* (wrapped) function not already tolerating a dead marker. If either is false, the guard is dead code or paternalistic. Worth a sentence on *when* the buffer could be killed between capture and use.
3. **"61 experim

... (truncated)
