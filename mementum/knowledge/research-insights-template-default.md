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

*3 check issues (severity 0.30). EXTRACTED from distill→check pipeline.*

```allium
# Distillation: 193 Experiments Across 36 gptel Modules

## Strategy Performance Assessment

`template-default` produced a large volume of hypotheses (193 experiments) but with shallow analytical depth — multiple kept hypotheses are near-duplicates (e.g., "adding defensive coding" vs. "adding error recovery and making assumptions explicit"), and discarded hypotheses were never analyzed (template placeholder left blank). The strategy is high-throughput but lacks discrimination pressure.

## Clustering of Kept Hypotheses

The surviving hypotheses collapse into **five recurring motifs**:

### 1. Redundancy Elimination
Remove guards that duplicate guarantees already provided by the underlying primitive.
- `if apply-lines` before `mapconcat` (mapconcat on empty list → "")
- Redundant callback existence checks before invocation
- **Pattern**: Caller adds defensive checks that are subsumed by callee semantics.

### 2. Defensive Guards (nil/empty/type)
Insert explicit early returns for invalid inputs that currently fall through.
- `english-findings` nil guard
- `allium-spec` nil/empty-string guard
- `(symbolp backend)` type branch
- `where` nil guard before overlay creation
- `buffer-live-p` check inside async lambdas
- **Pattern**: Edge cases that currently rely on incidental behavior get explicit handling.

### 3. Explicit Error Signaling
Convert silent failures into distinguishable outcomes.
- Timeout sentinel value (vs. ambiguous nil)
- **Pattern**: Confusing success/failure signal (nil) becomes typed outcome.

### 4. Containment via `condition-case`
Isolate a single function's failure so the surrounding machinery survives.
- `gptel--fsm-next` wrapped → defaults to `ERRS`
- Overlay creation wrapped → task execution survives
- **Pattern**: One bad call shouldn't cascade into aborting the parent workflow.

### 5. Decomposition for Independent Evolution
Extract a subroutine so it can be improved without touching the dispatcher.
- `gptel-benchmark--select-provider` extracted from `gptel-benchmark-call-subagent`
- **Pattern**: The φ Vitality win comes from *isolation*, not from the extraction itself.

## Meta-Observations

1. **The two metrics correlate by construction.** Every kept hypothesis justifies itself as improving *both* φ Vitality (adapts to previously-implicit edge cases) *and* fractal Clarity (makes assumptions explicit). This is not an independent signal — it's a *restatement* of "the code got more defensive." Treat the dual-axis scoring as a single axis in practice.

2. **No hypothesis changed the algorithm.** All kept hypotheses are local, structural, defensive. None propose new selection strategies, new provider-isolation mechanics, or new benchmarking methodology. The strategy defaults to safe refactoring.

3. **"Defensive coding" appears as a hypothesis at least 3 times** without further specification. This is a smell — it means the strategy is producing vague, non-falsifiable proposals that pass review on rhetoric alone.

4. **Discarded hypotheses are wasted signal.** 193 experiments × ~3 hypotheses each ≈ 500+ proposals. The discarded bucket is unanalyzed, so we cannot learn from the failures. A future strategy should require a *reason for rejection* (even one sentence) to convert discarded items into a negative-evidence dataset.

## Recommended Action

**Triage the 36 targets by highest-leverage overlap.** The five motifs above will appear in nearly every Emacs-Lisp file in the codebase. Rather than applying them mechanically across 36 files:

- **Prioritize targets with async callbacks, FSM transitions, and external IO** — these are where containment (`condition-case`) and explicit error signals pay off.
- **Defer targets that are pure data transformations** — defensive guards add noise without value when the callee already validates.
- **Re-run with `hypothesis-rejection-reason` required**, to recover the discarded bucket as useful signal.
- **Score on a single axis** until the φ/Clarity definitions are formally separated; right now they measure the same thing twice.
```

### Check Issues

# Review of the Distillation Document

Overall, this is a strong, well-structured analysis with sharp methodological observations. The critique is mostly sound. Below: what works, what needs verification, and what's missing.

---

## What Works Well

### 1. The five-motif clustering is clean
The clusters are non-overlapping in intent and the **bolded "Pattern:" lines** do real work — they convert specific findings into transferable lessons. Motif #1 (redundancy elimination) and Motif #4 (`condition-case` containment) are the most actionable, and they're correctly identified as distinct.

### 2. Meta-observation #1 (φ/Clarity collapse) is the strongest finding
If every kept hypothesis improves both axes simultaneously, those axes aren't two dimensions — they're one dimension with a fancy name. This is a genuine methodological bug, not just a presentation issue. The "single axis in practice" claim is correct and understates the problem: the dual scoring is actively *misleading* because it gives the appearance of multidimensional evaluation.

### 3. Meta-observation #2 ("no algorithm change") is the strategic finding
This is the most important *process* insight. 193 experiments that never once propose a new selection strategy, new provider-isolation mechanic, or new benchmarking method isn't exploration — it's local search around the current implementation. The "safe refactoring" diagnosis is accurate and the opportunity cost is real.

### 4. The `hypothesis-rejection-reason` reco

... (truncated)
