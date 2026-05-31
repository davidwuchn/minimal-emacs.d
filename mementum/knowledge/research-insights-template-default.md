---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 0.2/10
allium-issues: 4
allium-severity: 0.00
allium-status: ok
---

# Research Strategy: template-default

*Consolidated from 48 experiments (2% keep rate).*

**Performance:** 1 kept / 0 discarded / 21 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-auto-workflow-projects.el` (1 kept / 9 failed)

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
- `lisp/modules/gptel-auto-workflow-projects.el` (1 kept / 9 failed)
- `lisp/modules/treesit-agent-tools-workspace.el` (1 failed)

## Allium Behavioral Coherence

*4 behavioral issues (severity 0.00). EXTRACTED from Allium v3 pipeline.*



## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.










## Allium Behavioral Spec (auto-generated, v3)

*4 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Research Strategy Distillation

## Summary
- **Strategy**: template-default
- **Experiments**: 65 across 10 targets
- **Status**: Active hypothesis testing on gptel-* modules

## Kept Hypotheses (7 total)

| # | Change | Vitality | Clarity |
|---|--------|----------|---------|
| 1 | Idempotency guard + symmetric disable function | Progressive improvement | Explicit assumptions |
| 2 | Fix misleading message + dir validation | — | Bug fix |
| 3 | `eq`→`equal` for cache + reorder checks | Adapts to usage patterns | Content vs identity-based |
| 4 | Extract buffer lookup with nil guards | Graceful FSM handling | Visible assumptions |
| 5 | `ignore-errors` + empty-list guard | Edge case adaptation | Explicit validity assumptions |
| 6 | `format-mode-line`→`mode-name` direct; `if`→`when` | Robustness | Reduced complexity |
| 7 | Filter `not-applicable` before sort | Latent bug fix | Explicit data filtering |

**Discarded**: 0
```

### Check Issues

# Review: Research Strategy Distillation

## Structure Assessment ✓
Clean, tabular format. Good separation of change rationale, impact, and explicitness.

## Observations

| Aspect | Comment |
|--------|---------|
| **Hypothesis framing** | Clear distinction between bug fixes (#2), robustness (#6), and latent issues (#7) |
| **Vitality column** | Mixes: improvement type ("Progressive"), FSM handling, edge case adaptation |
| **Clarity column** | Varies from bug fix (#2) to architectural notes (#3: "Content vs identity-based") |
| **Discarded: 0** | Unusual for 65 experiments—either high signal or lenient retention criteria |

## Potential Issues

1. **Term inconsistency**: "Vitality" used as improvement type in some rows, operational benefit in others
2. **Missing priority/ordering** among the 7 hypotheses
3. **No cost/risks column**—hard to assess if these are "quick wins" or substantial refactors
4. **65 experiments → 7 kept** (10.8% retention) could warrant analysis of what got filtered

## Suggestions

- Add a **category column**: {bug, perf, maintainability, robustness}
- Add **effort/risk** indicators
- Consider grouping related changes (e.g., #3 and #4 both touch cache/F SM concerns)

---

Want me to help refine the schema or analyze any specific hypothesis?
