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

*Consolidated from 181 experiments (4% keep rate).*

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

*6 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
## Distillation

**Strategy**: Template-default across 181 experiments spanning 20 targets (Emacs Lisp gptel auto-workflow, tools-agent, benchmark, and staging modules).

**Kept Hypotheses** (8 surviving, thematically clustered around *φ Vitality* + *fractal Clarity* metrics):

1. **Idempotency + symmetry** — Guard against re-adding active advice; extract a symmetric disable function. *(Dual-metric: progressive improvement + explicit assumptions.)*
2. **Bug fix (messaging + validation)** — Correct misleading message; add directory-existence validation.
3. **Cache: `eq` → `equal`** — Switch identity comparison to content comparison in `gptel-auto-workflow--normalized-projects`; reorder to check cache before `ensure-buffer-tables`. *(Assumption: invalidation should be content-based.)*
4. **Buffer lookup with nil guards** — Extract explicit validation sequence; make nil-FSM-state handling visible.
5. **Adaptive error recovery** — Wrap `file-attributes` in `ignore-errors`; add early guard for empty project lists.
6. **Simplify mode-line access** — Replace `format-mode-line` with direct `mode-name`; swap `if` for `when`; add nil-safety for buffer iteration.
7. **Score-alist `not-applicable` filter** — Pre-filter before sort in `gptel-benchmark-eight-keys-weakest` to prevent `<` comparison crash on symbols. *(Latent-bug-driven.)*

**Discarded**: 0 (template-default discarded none).

**Pattern**: All keepers are *small, surgical, dual-metric* changes — no architectural rewrites. Two classes dominate: (a) **hardening** (idempotency, nil guards, content-equality, error recovery, filter-before-sort) and (b) **clarification** (extract symmetric pair, reorder for intent, drop redundant `format-mode-line`). The `not-applicable` hypothesis is the only one explicitly triggered by a discovered runtime defect.
```

### Check Issues

# Review of Distillation

## 🔴 Critical Inconsistency

**Count mismatch**: Header states "8 surviving, thematically clustered" — the numbered list contains **only 7** hypotheses (1–7). Either the count is wrong, or one hypothesis is missing. If #2's "messaging + validation" actually represents two sub-hypotheses that got merged, that would reconcile the count — but it's not labeled that way.

## 🟡 Pattern-Classification Math

The "Pattern" section claims two classes dominate, with parenthetical examples:

- **(a) hardening** — 5 items listed: idempotency, nil guards, content-equality, error recovery, filter-before-sort
- **(b) clarification** — 3 items listed: extract symmetric pair, reorder for intent, drop redundant `format-mode-line`

5 + 3 = 8, but you only have 7 hypotheses. The reconciliation is that **#1 and #3 are double-counted** (each appears in both classes). That works, but it means:
- **Hypothesis #2 (bug fix: messaging + validation) is unclassified** by the pattern. It fits hardening loosely (validation), but isn't enumerated.
- The phrasing "two classes dominate" obscures the fact that they overlap in 2/7 cases.

## 🟡 Inconsistent Metric Tagging

The header advertises "*φ Vitality* + *fractal Clarity* metrics" but only **#1 explicitly carries a "Dual-metric" tag**. The others use varied ad-hoc labels:

| # | Tag |
|---|---|
| 1 | "Dual-metric: progressive improvement + explicit assumptions" |
| 2 | (none) |
| 3 | "Assumption: invalidation should be content-based" |
| 4

... (truncated)
