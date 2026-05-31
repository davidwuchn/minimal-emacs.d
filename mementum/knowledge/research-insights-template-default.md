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

*Consolidated from 37 experiments (3% keep rate).*

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

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.




















## Allium Behavioral Spec (auto-generated, v3)

*0 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Research Strategy: Distilled

## Overview
- **Strategy**: template-default
- **Scope**: 65 experiments across multiple Elisp modules

## Targets
- `gptel-auto-workflow-*` modules (integration, strategic, projects)
- `gptel-benchmark-*` modules (subagent, principles)
- `gptel-tools-agent-*` modules (error, prompt-build)

## Key Hypotheses (Kept)

| # | Change | Benefits |
|---|--------|----------|
| 1 | Idempotency guard for advice + symmetric disable | Vitality, Clarity |
| 2 | Fix misleading message + directory validation | Bug fix |
| 3 | `equal` vs `eq` for cache; reorder cache check | Vitality, Clarity |
| 4 | Buffer lookup validation sequence + nil guards | Vitality, Clarity |
| 5 | Error recovery for invalid paths + empty list handling | Vitality, Clarity |
| 6 | `format-mode-line` → direct `mode-name`; `when` vs `if` | Clarity |
| 7 | Filter `not-applicable` before sorting | Clarity, Vitality |

## Discarded Hypotheses
None recorded.
```

### Check Issues

# Review: Research Strategy

## Structure & Format ✓
Clean, scannable layout. The hypothesis table is well-organized.

## Questions & Observations

### Scope
- **65 experiments** seems aggressive. Have you validated this count? Would help to see the experiment breakdown.

### Hypothesis Specifics
| # | Observation |
|---|-------------|
| 1 | "Symmetric disable" is mentioned but not defined. Needs elaboration. |
| 2 | "Fix misleading message" — which message? Specificity helps. |
| 3 | Cache check reordering: ensure this doesn't break existing users who rely on current behavior. |
| 6 | `format-mode-line` → `mode-name`: Confirm `mode-name` accepts the return type. |

### Missing Elements
- **Prioritization**: Which hypotheses are highest confidence/effort ratio?
- **Risk level**: Any changes that could break backward compatibility?
- **Discarded hypotheses**: "None recorded" is suspicious. Even a "none yet" note would be more credible.
- **Success metrics**: How will you measure "Vitality" and "Clarity" improvements?

### Minor
- "Vitality" as a benefit category is ambiguous — consider renaming to something more concrete (e.g., "Performance", "Stability").

---

**Overall**: Solid framework. The main gaps are in specificity and prioritization. Want me to suggest a restructuring or dive deeper into any hypothesis?
