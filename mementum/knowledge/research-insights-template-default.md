---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 0.2/10
allium-issues: 0
allium-severity: 0.00
allium-status: coherent
---

# Research Strategy: template-default

*Consolidated from 57 experiments (2% keep rate).*

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

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.


























## Allium Behavioral Spec (auto-generated, v3)

*0 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Research Strategy Distillation

## Scope
- **65 experiments** across 10 targets in `gptel/` module system

## Core Hypotheses (Kept/Active)

| Focus | Hypothesis | Targets |
|-------|-----------|---------|
| **Idempotency** | Add guard to prevent re-adding active advice; extract symmetric disable | workflow-research, workflow-strategic |
| **Cache validation** | Use `equal` instead of `eq` for project list comparison; check cache before `ensure-buffer-tables` | workflow-projects |
| **Buffer lookup** | Extract to validation sequence with explicit nil guards | (general) |
| **Edge cases** | `ignore-errors` around `file-attributes`; early guard for empty projects | workflow-projects |
| **Mode-line** | Direct `mode-name` access instead of `format-mode-line`; use `when` not `if` | (general) |

## Bug Fixes
- Misleading error messages
- Directory existence validation

## Discarded
- `gptel-benchmark-eight-keys-weakest`: Runtime crash on `not-applicable` symbols during sorting → filter before sort

## Design Principles
- **φ Vitality**: Adaptive error recovery, handles edge cases gracefully
- **Fractal Clarity**: Explicit assumptions, visible logic flow, nil-safety
```

### Check Issues

# Review: Research Strategy Distillation

## Overall Assessment: ✅ Solid Foundation

The distillation is well-structured with clear hypothesis-driven organization.

---

## Strengths

| Aspect | Evaluation |
|--------|------------|
| **Hypothesis-driven** | Each focus has explicit expected behavior changes |
| **Active vs Discarded** | Clear separation prevents dead-end exploration |
| **Specificity** | Concrete code-level fixes (`equal` vs `eq`, `when` vs `if`) |
| **Design Principles** | φ Vitality + Fractal Clarity provide decision-making criteria |

---

## Observations / Questions

### 1. Scope Feasibility
> 65 experiments × 10 targets = 650+ test cases?

Is there a prioritization mechanism? Consider tagging hypotheses as P0/P1/P2.

### 2. Idempotency Hypothesis
```elisp
;; "Extract symmetric disable" - does this mean:
(advice-add 'foo :before #'guard)   ; symmetric to
(advice-remove 'foo #'guard)
```
Clarify whether "symmetric disable" refers to advice removal, mode toggling, or both.

### 3. Mode-line Entry
```elisp
;; Direct mode-name vs format-mode-line
;; Risk: mode-name may be a list, not string
(when (stringp mode-name) ...)  ; still needed?
```

### 4. Discarded Experiment
> `not-applicable` symbols during sorting → filter before sort

Is this documented in a bug tracker? Could it be a linting target instead of experiment discard?

---

## Suggestions

| Area | Recommendation |
|------|----------------|
| **Hypothesis table** | Add "Status" column (e.g., Implemented/In Progress/Pending) |
| **φ Vita

... (truncated)
