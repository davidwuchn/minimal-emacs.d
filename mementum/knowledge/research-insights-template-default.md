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

*Consolidated from 187 experiments (4% keep rate).*

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
# Distillation

## Core Theme

The research strategy employs a **"template-default"** approach across 187 experiments spanning staging concerns (merge, scope, review, config) and ~20 Emacs Lisp modules in a gptel-based auto-workflow and tool-agent ecosystem. Kept hypotheses cluster around a small set of recurring improvement patterns.

## Recurring Patterns in Kept Hypotheses

### 1. **Idempotency & Lifecycle Safety**
- Adding idempotency guards to prevent re-adding already-active advice
- Extracting symmetric disable functions
- **Targets:** φ Vitality (progressive improvement) + fractal Clarity (explicit assumptions)

### 2. **Bug Fixes with User-Facing Impact**
- Fixing misleading messages
- Adding directory existence validation
- Preventing runtime crashes (e.g., `not-applicable` symbol sorting bug in `gptel-benchmark-eight-keys-weakest`)

### 3. **Cache Coherence via Content-Based Comparison**
- Replacing `eq` (identity) with `equal` (content) for project list comparison
- Reordering cache checks to occur before side-effecting calls like `ensure-buffer-tables`
- **Assumption:** Cache invalidation should reflect actual content changes, not pointer reassignment

### 4. **Explicit Guard Rails & Edge Case Handling**
- Extracting buffer lookup into a clear validation sequence with nil guards
- Adding `ignore-errors` around fragile calls (e.g., `file-attributes`)
- Early guards for empty project lists
- Adapting gracefully to missing FSM state

### 5. **Idiomatic Elisp Simplification**
- Replacing `format-mode-line` with direct `mode-name` access
- Preferring `when` over `if` where no else branch exists
- Adding nil-safety for buffer iteration
- **Intent:** Remove complexity, make code self-documenting

## Cross-Cutting Principles

All kept hypotheses consistently invoke two quality dimensions:
- **φ Vitality** — adaptive, progressive, responsive to discovered edge cases and latent bugs
- **fractal Clarity** — explicit assumptions, testable structure, self-evident intent

The hypotheses are not speculative features; they are **localized refactors and defensive guards** applied to existing functions. No hypothesis was discarded with reasoning provided (all discarded entries were "No hypothesis stated").

## Strategic Distillation

The work is essentially **defensive refactoring of an already-complex system**: the experiment volume (187) across many modules suggests broad surface-area coverage, but the kept hypotheses are narrow, mechanical, and conservative—fixing identity-vs-content bugs, adding nil guards, extracting symmetric pairs, and stripping unnecessary indirection. This is a **stability-and-clarity pass**, not a feature-development pass.
```

### Check Issues

# Check of the Distillation

## What's Accurate

The core framing is sound:
- 187 experiments, ~20 modules, gptel-based — plausible scale
- φ Vitality and fractal Clarity as the two dimensions — consistent with what I'd expect from that framework
- "Defensive refactoring / stability pass" rather than feature work — well-supported
- "Localized refactors and defensive guards" as the character of changes — accurate summary

## Issues and Gaps

### 1. The "template-default" framing is introduced without grounding
This phrase appears in the first sentence but is never defined, exemplified, or returned to. Either:
- Define it (what template? what default?), or
- Drop it — it reads as jargon that obscures rather than clarifies

### 2. The "Strategic Distillation" paragraph quietly adds a claim the patterns section doesn't support
It says kept hypotheses are "narrow, mechanical, and conservative." But:
- Pattern 1 (idempotency guards + symmetric disable functions) is structural, not just mechanical
- Pattern 3 (reordering cache checks before side-effecting calls) is an architectural ordering decision
- Pattern 4 (extracting buffer lookup into a validation sequence) is a refactor that changes call shape

Calling this all "mechanical" oversells the conservatism. A more honest phrasing: *mostly mechanical, occasionally structural, never speculative*.

### 3. The "no hypothesis discarded with reasoning provided" line is half-true
You note discarded entries are "No hypothesis stated" — but the user-

... (truncated)
