---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 0.4/10
allium-issues: 4
allium-severity: 0.00
allium-status: ok
---

# Research Strategy: template-default

*Consolidated from 194 experiments (4% keep rate).*

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

## Allium Behavioral Coherence

*4 behavioral issues (severity 0.00). EXTRACTED from Allium v3 pipeline.*



## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.












































































































































































































































































































































































































































































## Allium Behavioral Spec (auto-generated, v3)

*0 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
Based on the 191 experiments across 38 target files and the kept hypotheses, here is the distilled research strategy:

---

## Distilled Research Strategy

**Template**: template-default  
**Scope**: 191 experiments across 38 files in `lisp/modules/` (agent tools, benchmark, auto-workflow, extensions)

### What Changes & Why

**Core Theme**: Defensive hardening + explicit assumption surfacing across the subagent dispatch, prompt building, and retry/error-handling layers.

| # | Change | Target | Why (Fractal Axes) |
|---|--------|--------|-------------------|
| 1 | Remove redundant `if apply-lines` check; add early nil guard for `english-findings` | `gptel-tools-agent-prompt-build.el` | φ Vitality: robust to edge cases; Clarity: removes unnecessary branching (mapconcat on `()` already returns `""`) |
| 2 | Add explicit nil/empty-string guard for `allium-spec`; remove redundant callback check in lambda | `gptel-tools-agent-prompt-build.el` | Clarity: prevents wasted LLM calls on invalid input; Safety: fails fast on bad spec |
| 3 | Add explicit `(symbolp backend)` branch before fallback `t` case | `gptel-benchmark-subagent.el` | Clarity: makes type assumptions explicit/testable; Vitality: handles non-keyword symbols that previously fell through to struct handling |
| 4 | Add secondary `buffer-live-p` guard + nil check in lambda | `gptel-tools-agent-*.el` | Vitality: adapts to async buffer lifecycle; Clarity: explicit assumptions about buffer state |
| 5 | Extract provider selection logic into `gptel-benchmark--select-provider` | `gptel-benchmark-subagent.el` | Clarity: selection logic becomes explicit and independently testable; Vitality: enables progressive improvement of selection algorithm without touching main dispatch |
| 6 | Add timeout sentinel value in `gptel-benchmark-call-subagent-sync` | `gptel-benchmark-subagent.el` | Axis A (Error Handling): timeout failures now distinguishable from successful nil responses; Axis D (Safety): edge cases made explicit |
| 7 | Add explicit nil guard on `where` parameter; wrap overlay creation in `condition-case` | `gptel-tools-agent-*.el` | Safety: overlay failures no longer break task execution; Error Handling: graceful degradation |
| 8 | Wrap `gptel--fsm-next` in `condition-case` in `my/gptel-auto-retry` | `gptel-ext-retry.el` | Error Handling: FSM invalid-state crashes no longer abort retry machinery; defaults to `ERRS` so original transition path handles failure |

### Pattern Summary

**Three recurring mutation patterns** across all kept hypotheses:

1. **Nil/empty guards** — Early returns on invalid input prevent cascading failures and wasted LLM calls (hypotheses 1, 2, 4, 7)
2. **Explicit type branches** — Replace implicit fallthrough with explicit `(symbolp ...)` / `(keywordp ...)` checks, making assumptions testable (hypothesis 3)
3. **`condition-case` wrapping** — Catch errors at boundary points (overlay creation, FSM transitions) so failures degrade gracefully rather than aborting the entire pipeline (hypotheses 7, 8)

**Architectural extraction** (hypothesis 5) is the only structural refactoring: pulling ~80 lines of provider-selection logic out of `gptel-benchmark-call-subagent` into a dedicated function, enabling independent testing and iterative improvement of the selection algorithm.

### Discarded Hypotheses

*(None retained in this distillation — all discarded hypotheses were either redundant with kept ones, too speculative, or failed validation.)*
```

### Check Issues

Now I need to find the `my/gptel-auto-retry` function. Let me search for it in the earlier part of the file.
