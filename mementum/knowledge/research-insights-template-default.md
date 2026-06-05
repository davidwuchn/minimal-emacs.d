---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 0.4/10
allium-issues: 0
allium-severity: 0.05
allium-status: coherent
---

# Research Strategy: template-default

*Consolidated from 180 experiments (4% keep rate).*

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

*0 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Distillation

## Research Strategy
**Template-default** applied across 180 experiments, with no alternative strategy deployed.

## Target Coverage
Experiments spanned 19 targets across four functional clusters:

| Cluster | Targets |
|---------|---------|
| **Staging pipeline** | staging-merge, staging-scope, staging-review, staging-config |
| **Auto-workflow** | ontology-router, ontology-strategy, evolution, mementum, bootstrap, projects, production-metrics, strategic |
| **Tools agent** | error, runtime, benchmark, prompt-build, experiment-core |
| **Benchmark/framework** | gptel-benchmark-subagent, gptel-benchmark-principles |

## Hypotheses Kept — Recurring Patterns

The 8 surviving hypotheses converge on **two intertwined principles**: **φ Vitality** (progressive improvement that adapts to discovery) and **fractal Clarity** (explicit, testable assumptions). Concrete recurring patterns:

1. **Idempotency + symmetric extraction** — guard against re-adding active advice; pair enable/disable functions symmetrically.
2. **Bug fixes paired with validation** — correct misleading messages; add directory/file existence checks.
3. **Identity → content comparison** — `eq` → `equal` for cache keys; cache should invalidate on semantic change, not pointer change. Reorder to check cache *before* expensive setup (`ensure-buffer-tables`).
4. **Explicit nil guards** — extract buffer lookups into validation sequences that fail gracefully on missing FSM state.
5. **Edge-case recovery** — `ignore-errors` around `file-attributes`; early-exit on empty project lists.
6. **Construct simplification** — `format-mode-line` → direct `mode-name`; `if` with single branch → `when`; guard buffer iteration against nil.
7. **Latent-bug surfacing** — filter `not-applicable` sentinels before numeric sorting (prevents `(< 'not-applicable <number>)` crash in `gptel-benchmark-eight-keys-weakest`).

## Hypotheses Discarded
None — discarded set is empty (placeholder: "No hypothesis stated").

## Net Insight
The template-default strategy produced hypotheses that are uniformly **micro-refactors** in gptel's auto-workflow and tools-agent stack: each is small in scope, but each tightens an invariant (idempotency, content-equality, nil-safety, edge-case handling, latent-bug exposure). The dual lens of Vitality+Clarity appears to systematically surface the same class of issues — defensive guards around state and explicit assumptions about data shape — across otherwise unrelated modules.
```

### Check Issues

# Review of the Distillation Document

The document is well-structured and largely internally consistent, but there are several issues worth flagging — some factual, some presentational, and some concerning the framing.

## ✅ What's solid

- **Target count checks out**: 4 + 8 + 5 + 2 = 19. ✓
- **Concrete grounding**: Specific identifiers (`eq` → `equal`, `ensure-buffer-tables`, `not-applicable` sentinel, `gptel-benchmark-eight-keys-weakest`) make the patterns falsifiable rather than hand-wavy.
- **Honest about gaps**: Explicitly noting the empty discarded-hypothesis section is good epistemic hygiene.
- **Net Insight is appropriately scoped**: "uniformly micro-refactors" is a defensible characterization given the cited examples.

## ⚠️ Issues to address

### 1. Undefined framing vocabulary
**"φ Vitality"** and **"fractal Clarity"** are used as load-bearing organizing principles but never defined. A reader cannot evaluate whether the patterns actually instantiate these concepts, because the concepts themselves are not specified. As written, "Vitality" ≈ "improvement" and "fractal" ≈ "explicit" — but those reductions aren't given.

### 2. Stylistic asymmetry
If the two principles are meant to be parallel, "φ Vitality" and "fractal Clarity" should share formatting. Pick one convention: either both are Latin-initial capitals or both are uncapitalized, and decide whether φ is a meaningful label or a typographic flourish (currently unclear).

### 3. The 8 hypotheses ↔ 7 patterns gap
You 

... (truncated)
