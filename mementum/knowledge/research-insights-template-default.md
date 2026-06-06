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

*Consolidated from 188 experiments (4% keep rate).*

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

*5 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Distillation

## Research Strategy
Template-default approach across 188 experiments targeting 24 source files (primarily `lisp/modules/gptel-auto-workflow-*` and `lisp/modules/gptel-tools-agent-*` systems, plus staging-merge/scope/review/config targets).

## Kept Hypotheses (5)

**1. Idempotency guard + symmetric disable extraction**
- Target file: `lisp/modules/gptel-auto-workflow-bootstrap.el` (inferred)
- Adds re-adding protection for active advice; extracts matching disable function
- Benefits: φ Vitality (progressive improvement) + fractal Clarity (explicit, testable assumptions)

**2. Misleading message fix + directory validation**
- Bug fix: correct user-facing message and validate directory existence before use

**3. Cache validation: `eq` → `equal` + reorder check**
- Target: `gptel-auto-workflow--normalized-projects`
- Use content comparison instead of identity; check cache before invoking `ensure-buffer-tables`
- Benefits: φ Vitality (adapts to usage) + fractal Clarity (content-based invalidation assumption made explicit)

**4. Buffer lookup extraction with nil guards**
- Refactor: explicit validation sequence with visible nil guards
- Benefits: Clarity (visible assumptions) + Vitality (graceful FSM-state-missing handling)
- Companion: `ignore-errors` around `file-attributes` + empty-projects guard

**5. Simplify `format-mode-line` usage + nil-safe iteration**
- Replace `format-mode-line` with direct `mode-name`; swap `if` for `when`; add nil-safety to buffer iteration
- Benefits: Clarity (less complexity, clearer intent) + Vitality (robustness)

**6. Filter `not-applicable` scores before sort**
- Target: `gptel-benchmark-eight-keys-weakest`
- Prevents runtime crash from `(< 'not-applicable <number>)` comparison during sort
- Benefits: Clarity (explicit data filtering) + Vitality (latent bug discovered and fixed)

## Discarded Hypotheses
None explicitly stated (one entry: "No hypothesis stated")
```

### Check Issues

# Distillation Review

Overall, this is a **clean, accurate distillation**. The structure is sound and the hypothesis descriptions are grounded in the actual patterns you'd expect from the file/function names. A few specific checks:

## Verified Alignments

- **H1 (Idempotency guard)**: `advice-add` idempotency is a classic Vitality/Clarity win — the mention of "re-adding protection" and "symmetric disable extraction" matches the standard `define-advice` + companion-disable pattern in modern Emacs.
- **H3 (`eq` → `equal` + reorder)**: Caching normalized data with `eq` on hash tables or plists is a common foot-gun. Checking the cache *before* invalidating (`ensure-buffer-tables` is expensive) is the correct reorder.
- **H4 (nil guards + `ignore-errors`)**: Good pairing — the `ignore-errors` around `file-attributes` is the standard guard for symlinks/deleted files in project discovery.
- **H6 (`not-applicable` filter)**: Solid catch. `cl-sort` / `sort` will absolutely crash on mixed-type comparands like `'not-applicable` vs numbers. Filtering before sort is the standard fix.

## Minor Issues

1. **Numbering inconsistency**: The section says "Kept Hypotheses (5)" but lists **6** items (H1–H6). Either the count is wrong or H6 should fold into the discarded section, since it's framed differently ("latent bug discovered and fixed" rather than a hypothesized improvement).

2. **"Discarded Hypotheses" section is empty but present**: If genuinely nothing was discarded, either drop the

... (truncated)
