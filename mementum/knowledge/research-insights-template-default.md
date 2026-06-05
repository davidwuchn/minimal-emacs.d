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

*Consolidated from 176 experiments (4% keep rate).*

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
<think>
The user wants me to "distill" research that was conducted using a "template-default" strategy across 176 experiments. The output should be a distillation of the kept hypotheses, since the discarded ones only contain "No hypothesis stated" entries.

Let me look at what was kept:

1. **Idempotency guard + symmetric disable** - Targets φ Vitality and fractal Clarity
2. **Fix misleading message + directory validation** - Bug fix
3. **Cache validation uses `eq` instead of `equal`** - Change to content-based comparison
4. **Extract buffer lookup with explicit nil guards** - Clarity/Vitality
5. **Adaptive error recovery for invalid project paths + empty-projects edge case** - φ Vitality/fractal Clarity
6. **Replace `format-mode-line` with `mode-name` + `when` instead of `if`** - fractal Clarity
7. **`gptel-benchmark-eight-keys-weakest` runtime crash on `not-applicable` symbols** - Filter before sorting

The user wants these distilled. "Distill" typically means to extract the essence, find common patterns, or create a more concentrated/refined version. Given the context of "template-default" research strategy with 176 experiments, the distillation should:
- Identify common themes
- Remove redundancy
- Group by category/principle
- Make patterns visible

Let me think about what these hypotheses share:

**Common themes:**
1. **Defensive programming** - nil guards, validation, idempotency, error recovery (hypotheses 1, 2, 3, 4, 5, 6, 7)
2. **φ Vitality** (adapts to discovery, new information, edge cases) - appears in 1, 3, 4, 5, 7
3. **fractal Clarity** (explicit assumptions, testable, removes complexity) - appears in 1, 3, 4, 5, 6
4. **Comparison/equality semantics** - hypothesis 3 (eq vs equal)
5. **Filtering/preconditioning** - hypothesis 7 (filter not-applicable)
6. **Bug fixes vs improvements** - hypothesis 2 is explicit bug fix

**Categories I can extract:**
- **Precondition validation** (hypotheses 2, 4, 5, 7) - validating inputs/state before processing
- **Identity vs content semantics** (hypothesis 3) - choosing right comparison
- **Idempotency / lifecycle symmetry** (hypothesis 1) - paired add/remove operations
- **Complexity reduction** (hypothesis 6) - removing unnecessary indirection

**Underlying principle:**
All hypotheses are about making code more robust to its actual operating environment - whether that's edge cases, runtime errors, identity mismatches, or unnecessary work. They all target two of the seven hermetic principles: φ Vitality and fractal Clarity.

Let me write a distillation that:
1. Identifies the meta-pattern
2. Groups hypotheses by category
3. Shows the principle coverage
4. Is concise but preserves the substance

Format-wise, since there's no formatting instruction, I should be reasonably structured. Markdown with headers seems appropriate for a research distillation. I shouldn't be too verbose. The user said "distill" - so be concise.

Let me also note: the "Discarded hypotheses" section is entirely empty except for "No hypothesis stated" — so the discarded list yields nothing. I should acknowledge that briefly or just focus on the kept ones.

I'll structure the distillation as:
1. Brief framing of what the experiments converged on
2. The meta-pattern
3. Categorized hypotheses
4. Principle coverage
5. Maybe a note on what's not covered (gaps)
</think>
```

