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

*Consolidated from 179 experiments (4% keep rate).*

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

*7 check issues (severity 0.05). EXTRACTED from distill→check pipeline.*

```allium
# Distilled Research Summary

## Approach
**Strategy:** template-default across 179 experiments targeting 18 gptel-related Emacs Lisp files (staging + module sources).

## Surviving Hypotheses (4 → grouped by intent)

### 1. Robustness via Idempotency & Error Recovery
- **Advice re-entry guard** + symmetric disable extraction → prevents double-application, makes lifecycle symmetric.
- **`not-applicable` symbol filter** in `gptel-benchmark-eight-keys-weakest` → prevents `(< 'not-applicable <number>)` runtime crash during sort.
- **Adaptive error recovery** for invalid project paths (`ignore-errors` around `file-attributes`) + empty-projects early guard.

**φ Vitality:** adapts to discovered edge cases and latent bugs.
**fractal Clarity:** makes validity assumptions explicit and testable.

---

### 2. Cache Correctness (Identity → Content Semantics)
`gptel-auto-workflow--normalized-projects` uses `eq` on the project list, forcing unnecessary invalidation when `gptel-auto-workflow-projects` is reassigned to an equivalent new list.
- Switch to `equal` (content comparison).
- Reorder: check cache **before** invoking `ensure-buffer-tables`.

**φ Vitality:** matches actual usage patterns rather than memory identity.
**fractal Clarity:** encodes the explicit assumption *invalidation should be content-based*.

---

### 3. Explicit Validation Sequencing
Extract buffer lookup into a named validation chain with explicit `nil` guards (instead of inline checks). Handles missing FSM state gracefully.

**Clarity:** assumptions become visible in the call shape.
**Vitality:** degrades cleanly when downstream state is absent.

---

### 4. Surface-Level Simplifications
- Replace `format-mode-line` with direct `mode-name` access.
- `if` → `when` where there's no else branch.
- Add nil-safety to buffer iteration.

**Clarity:** removes gratuitous indirection; intent is locally readable.

---

## Discarded
- 1 entry: *"No hypothesis stated"* — noise from an unprompted target.

## Pattern Across Survivors
Every kept hypothesis trades **implicit/runtime behavior** for **explicit/assumed** behavior, and **memory-identity or symbol-trapping semantics** for **content-or-shape semantics** — a consistent refinement from accidental correctness to asserted correctness.
```

### Check Issues

# Review of Distilled Research Summary

## What's Solid

**The meta-pattern at the end is the strongest part of this document.** The observation that survivors consistently trade *implicit/runtime* for *explicit/assumed* and *identity* for *content/shape* semantics is a genuine insight, not boilerplate. "Accidental correctness → asserted correctness" is a useful framing for code review.

**Hypothesis 2 (Cache Correctness) is the most defensible.** The `eq` vs `equal` distinction is real and the scenario it describes (reassignment of a list to an equivalent new list forcing invalidation) is a textbook identity-vs-equality bug. The reorder recommendation also has a clear rationale — fail fast on cache hit before paying for side-effect work.

**Hypothesis 1's first sub-point** (the `(< 'not-applicable <number>)` crash) is a concrete, verifiable runtime bug. Good.

**The Discarded section is honest** — admitting that most of 179 experiments produced noise rather than signal is useful.

---

## What Needs Verification or Context

1. **The `eq` → `equal` switch has a cost you don't acknowledge.** `equal` on a list is O(n); `eq` is O(1). If the cache is hit on every request, this is a real tradeoff. The summary asserts "matches actual usage patterns" but doesn't show that the perf delta is acceptable. Worth measuring or noting as a residual risk.

2. **The reorder in Hypothesis 2** ("check cache **before** invoking `ensure-buffer-tables`") assumes `ensure-buffer-tables` is either pure 

... (truncated)
