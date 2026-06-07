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

*Consolidated from 218 experiments (3% keep rate).*

**Performance:** 7 kept / 1 discarded / 12 failed (EXTRACTED — from TSV)

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
- `lisp/modules/gptel-auto-workflow-production-metrics.el` (1 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.
















## Allium Behavioral Spec (auto-generated, v3)

*0 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Distilled Research Strategy

## Scope
**218 experiments** across 33 target files in the `gptel-auto-workflow`, `gptel-tools-agent`, `gptel-benchmark`, and `staging-*` modules.

## Kept Hypotheses (6)

| # | Hypothesis | Target Principle |
|---|------------|------------------|
| 1 | **Idempotency guard**: Prevent re-adding active advice + extract symmetric disable function | φ Vitality, fractal Clarity |
| 2 | **Bug fix**: Fix misleading message + add directory existence validation | Bug fix |
| 3 | **Cache validation**: Replace `eq` with `equal` for project list comparison; check cache before `ensure-buffer-tables` | φ Vitality, fractal Clarity |
| 4 | **Buffer lookup**: Extract validation sequence with explicit nil guards | Clarity, Vitality |
| 5 | **Error recovery**: Add `ignore-errors` around `file-attributes` + early guard for empty project lists | φ Vitality, fractal Clarity |
| 6 | **Mode line**: Replace `format-mode-line` with direct `mode-name` access; use `when` instead of `if`; add nil-safety guard | fractal Clarity, φ Vitality |
| 7 | **Benchmark crash fix**: Filter `not-applicable` entries before sorting in `gptel-benchmark-eight-keys-weakest` | Clarity, Vitality |

## Discarded Hypotheses
- None stated

## Core Themes
- **φ Vitality**: Adaptive error recovery, content-based caching, nil-safety guards
- **fractal Clarity**: Explicit assumptions, simplified control flow, visible validation sequences
- **Bug fixes**: Idempotency, misleading messages, runtime crashes from symbol comparison
```

### Check Issues

## Check Results

**❌ Inconsistency Found**

| Issue | Detail |
|-------|--------|
| **Count mismatch** | Header says **6** hypotheses, but table lists **7** (numbered 1–7) |

### Quick Fix Options

**Option A** — Update the header to match the table:
```markdown
## Kept Hypotheses (7)
```

**Option B** — If one hypothesis should be removed, clarify which one and renumber.

---

### Other Observations

| Check | Status |
|-------|--------|
| Numbering sequence | ✅ 1–7, no gaps |
| Target principles referenced | ✅ Consistent use of φ Vitality / fractal Clarity |
| Discarded section | ⚠️ "None stated" — consider explicitly listing what was evaluated and dropped, or remove the section |
| Scope line | ✅ Clear module list |
| Core themes | ✅ Map well to the hypotheses |

**Recommendation:** Fix the count mismatch first. If all 7 are intentional, just update the header number.
