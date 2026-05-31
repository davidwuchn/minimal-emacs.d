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

*Consolidated from 61 experiments (2% keep rate).*

**Performance:** 1 kept / 3 discarded / 21 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-auto-workflow-projects.el` (1 kept / 2 discarded / 9 failed)

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

- `lisp/modules/gptel-tools-agent-prompt-build.el` (4 failed)
- `lisp/modules/gptel-tools-agent-error.el` (2 failed)
- `lisp/modules/gptel-benchmark-principles.el` (2 failed)
- `lisp/modules/gptel-auto-workflow-projects.el` (1 kept / 2 discarded / 9 failed)
- `lisp/modules/treesit-agent-tools-workspace.el` (1 failed)

## Allium Behavioral Coherence

*3 behavioral issues (severity 0.05). EXTRACTED from Allium v3 pipeline.*



## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.


















## Allium Behavioral Spec (auto-generated, v3)

*0 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Research Strategy Distillation: `template-default`

## Summary

**61 experiments** conducted across 14 Emacs Lisp targets. **No hypothesis was stated.** **No hypotheses were retained.**

## Discarded Findings

Three specific improvements identified but not applied:

1. **`lisp/modules/gptel-tools-memory.el` L362** — Redundant type checks (`consp val`/`keywordp`) already encoded downstream; speculative `make-hash-table` allocation inside guard. Suggested: move allocation, use `ignore-errors` instead of `condition-case nil`.

2. **`lisp/modules/gptel-auto-workflow-research.el`** — Empty `status-lines` lacks nil guard, risking empty-result caching. Suggested: explicit edge-case handling.

3. **Indentation fixes** — Misleading indentation in `gptel-auto-workflow-run-all-projects` and `gptel-auto-workflow--get-worktree-buffer` misrepresents parse-tree structure.

## Bottom Line

The experiment catalog is large but unfocused—no stated hypothesis to validate, no kept conclusions. The 3 discarded items represent concrete code quality issues (allocation waste, missing guards, visual misrepresentation) that remain unaddressed.
```

### Check Issues

## Assessment

**Valid critique.** The summary has a structural problem worth naming:

### What works
- Concrete, specific discarded findings with file locations
- Distinguishes between *volume* (61 experiments) and *value* (zero retained conclusions)

### What doesn't

| Issue | Problem |
|-------|---------|
| No hypothesis | Experiments can't be evaluated without a stated goal |
| No retained conclusions | Knowledge gained wasn't captured for reuse |
| Discarded items not applied | Finding problems without fixing them has zero value |

### The core issue

61 experiments without a hypothesis is *activity*, not *research*. The three discarded findings are actually the only actionable output—code quality issues that could be submitted as patches regardless of the broader experiment's failure.

### Recommendation

If this is archival: **don't keep the experiment catalog**. The 3 discarded findings are worth a PR; the rest is noise.

If iterating: restate the question before running more experiments.
