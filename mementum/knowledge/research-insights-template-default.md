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

*Consolidated from 192 experiments (4% keep rate).*

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

*4 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
The user is asking me to "distill" research findings. They've provided a research strategy, experiments, and lists of kept and discarded hypotheses. I need to synthesize this into a clear, organized distillation.

Let me analyze the kept hypotheses:

1. Idempotency guard + symmetric disable function — Vitality + Clarity
2. Fix misleading message + directory existence validation — bug fix
3. Cache validation uses `eq` instead of `equal` for project list — Vitality + Clarity
4. Extract buffer lookup with explicit nil guards — Clarity + Vitality
5. Adaptive error recovery for invalid project paths + empty-projects edge case — Vitality + Clarity
6. Replace `format-mode-line` with direct `mode-name` access + nil-safety guard — Clarity + Vitality
7. Filter `not-applicable` symbols before sorting in benchmark scoring — Clarity + Vitality

These are all about improvements to specific code areas, targeting two main values:
- φ Vitality (progressive improvement, adapts to discovery, robust to edge cases)
- fractal Clarity (explicit assumptions, testable, removes unnecessary complexity)

The discarded hypotheses section just says "No hypothesis stated" — so all the real findings are in the kept section.

Let me distill this into a clear summary that captures the patterns and themes. I should NOT add my own hypotheses — only synthesize what was provided.

The format should be a clean distillation. Let me think about what makes a good distillation:
- Group by theme
- Identify common patterns
- Note the values being targeted
- Preserve concrete actionable content

Patterns I see:
1. **Cache invalidation**: Move from identity to content comparison
2. **Idempotency / symmetry**: Guards against re-adding, extract disable counterparts
3. **Edge case handling**: nil guards, empty-list guards, ignore-errors around unsafe calls
4. **Data filtering**: Remove sentinel values (like `not-applicable`) before processing
5. **Simplification**: Replace complex calls with simpler direct ones (format-mode-line → mode-name)
6. **Validation**: Directory existence, buffer state assumptions
7. **Misleading messages**: Fix incorrect status/info messages

Common targets:
- φ Vitality: adapt to actual usage, robust to edge cases, learn from discovered bugs
- fractal Clarity: make assumptions explicit, simplify intent, testable

Let me write a clean distillation. I'll make it organized and actionable without adding new hypotheses.
```

### Check Issues

I see the issue. What you pasted isn't a distillation — it's a **planning document** (an LLM's meta-reasoning *about* how to distill). The actual research material is missing.

## What I can see in your message

- **7 kept hypotheses** (items 1–7), apparently from an Emacs Lisp codebase (references to `project-p`, `format-mode-line`, `mode-name`, `eq`/`equal`, `not-applicable` symbols)
- **No discarded hypotheses** — the discarded section is empty
- **No research strategy or experiments** — only the list of outcomes
- **The rest is the planner's own scratchpad** (pattern analysis, formatting ideas, etc.) — not findings

## What's missing to actually distill

To produce the distillation, I'd need:

1. The **research strategy / driving questions** that generated these hypotheses
2. The **experiments or evidence** (tests run, cases exercised) backing each kept item
3. The **discarded hypotheses with reasons** — the "No hypothesis stated" line suggests this wasn't filled in
4. The **full text of each kept hypothesis**, not just one-line summaries

## What I can offer right now

- **Check the planner's reasoning** — the thematic grouping (cache invalidation, idempotency, nil-guards, sentinel filtering, simplification) is sound, and the Vitality/Clarity framing is applied consistently
- **Check for gaps in the 7 kept items** — e.g., hypothesis #1 mixes two concerns (idempotency guard *and* symmetric disable), and #6 also bundles two changes; these should likely split if "distill" means *

... (truncated)
