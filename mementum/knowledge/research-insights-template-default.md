---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 1.0/10
allium-issues: 6
allium-severity: 0.00
allium-status: ok
---

# Research Strategy: template-default

*Consolidated from 72 experiments (10% keep rate).*

**Performance:** 7 kept / 0 discarded / 5 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-auto-workflow-projects.el` (6 kept / 2 failed)
- `lisp/modules/gptel-benchmark-principles.el` (1 kept / 2 failed)

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

- `lisp/modules/gptel-auto-workflow-strategic.el` (1 failed)
- `lisp/modules/gptel-auto-workflow-projects.el` (6 kept / 2 failed)
- `lisp/modules/gptel-benchmark-principles.el` (1 kept / 2 failed)

## Allium Behavioral Coherence

*6 behavioral issues (severity 0.00). EXTRACTED from Allium v3 pipeline.*



## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.






































































































































































































































































































































































































## Allium Behavioral Spec (auto-generated, v3)

*7 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
The user wants me to "distill" a research strategy log. This appears to be a log from an AI-assisted research/coding session with many experiments across multiple targets, kept hypotheses, and discarded hypotheses.

The raw text is quite messy:
- "Research strategy: template-default"
- "72 experiments across targets: [long list]"
- "Kept hypotheses:" followed by many blank lines, then several bullet points with hypotheses
- Some hypotheses are preceded by "Now let me implement the change. I need to:" which seems like stray implementation notes that got mixed into the hypotheses
- "Discarded hypotheses:" at the end with nothing after

I need to distill this into a clean, structured summary. The goal is to extract the essential information: what was researched, what hypotheses were kept, and what they target.

Let me parse the kept hypotheses:

1. Add idempotency guard to prevent re-adding advice that's already active, AND extract symmetric disable function. Targets: φ Vitality and fractal Clarity.
2. Fix misleading message and add directory existence validation. Bug fix type.
3. Cache validation in `gptel-auto-workflow--normalized-projects` uses `eq` (identity) causing unnecessary cache invalidation. Change to `equal` (content) and reorder to check cache before `ensure-buffer-tables`. Targets: φ Vitality and fractal Clarity.
4. Extract buffer lookup into clear validation sequence with explicit nil guards. Improves Clarity (visible assumptions) and Vitality (adapts to missing FSM state).
5. Function lacks adaptive error recovery for invalid project paths and doesn't handle empty-projects edge case. Add `ignore-errors` around `file-attributes` and early guard for empty project lists. Targets: φ Vitality and fractal Clarity.
6. (Embedded in implementation notes) Replacing `format-mode-line` with direct `mode-name` access and using `when` instead of `if` will improve fractal Clarity. Add nil-safety guard for buffer iteration. Targets: fractal Clarity and φ Vitality.
7. `gptel-benchmark-eight-keys-weakest` will crash at runtime when scoring with task-type hypothesis because `not-applicable` symbols cause `(< 'not-applicable <number>)` during sorting. Add filter for `not-applicable` entries before sorting. Targets: Clarity and Vitality.

Wait, looking closely, hypothesis 6 seems to be preceded by "Now let me implement the change. I need to:" which is not part of the hypothesis. Let me clean that up.

Also there are many blank lines after "Kept hypotheses:" - probably representing the 72 experiments or just formatting.

I should structure this as:

**Research Strategy**: template-default
**Scope**: 72 experiments across 11 targets (list them concisely)

**Kept Hypotheses** (grouped by target/theme if possible):
1. Idempotency & Symmetry: Add idempotency guard for advice + extract symmetric disable function. → Vitality, Clarity
2. Validation & Bug Fix: Fix misleading message + add directory existence validation. → Bug fix
3. Cache Semantics: Change `eq` to `equal` in `gptel-auto-workflow--normalized-projects` cache validation; reorder to check cache before `ensure-buffer-tables`. → Vitality, Clarity
4. FSM Resilience: Extract buffer lookup into explicit validation sequence with nil guards. → Clarity, Vitality
5. Edge Case Handling: Add `ignore-errors` for `file-attributes` and early guard for empty project lists. → Vitality, Clarity
6. Simplification: Replace `format-mode-line` with `mode-name`; use `when` instead of `if`; add nil-safety for buffer iteration. → Clarity, Vitality
7. Data Integrity: Filter `not-applicable` entries before sorting in `gptel-benchmark-eight-keys-weakest` to prevent runtime type errors. → Clarity, Vitality

**Discarded Hypotheses**: None recorded.

I should make this very concise and readable, removing the fluff and stray implementation notes. The user said "distill" so brevity is key.

Let me check if there are any other hypotheses I missed. The text has a lot of blank lines. Let me recount:

Line "- Add an idempotency guard..." ->
-- ... truncated ...
```

### Check Issues

**Research Strategy:** `template-default`  
**Scope:** 72 experiments across 11 targets — φ Vitality, fractal Clarity, Clarity, Sparsity, Temperance, Elasticity, FSM, Persistence, Governance, bug-fix, Λ archetype.

---

### Kept Hypotheses (7)

1. **Advice Idempotency & Symmetry**  
   Add an idempotency guard to prevent re-adding advice that is already active, and extract a symmetric `disable` function.  
   → *φ Vitality, fractal Clarity*

2. **UX / Validation Bug Fix**  
   Fix a misleading success message and add directory-existence validation.  
   → *bug-fix*

3. **Cache Semantics**  
   In `gptel-auto-workflow--normalized-projects`, the cache validation uses `eq` (identity), causing unnecessary invalidation. Switch to `equal` (content) and reorder so the cache is checked before `ensure-buffer-tables`.  
   → *φ Vitality, fractal Clarity*

4. **FSM Resilience**  
   Extract buffer lookup into a clear, explicit validation sequence with `nil` guards. Makes assumptions visible (Clarity) and lets the system adapt to a missing FSM state (Vitality).  
   → *fractal Clarity, φ Vitality*

5. **Edge-Case Hardening**  
   Add adaptive error recovery for invalid project paths (`ignore-errors` around `file-attributes`) and an early guard for empty project lists.  
   → *φ Vitality, fractal Clarity*

6. **Mode-Access Simplification**  
   Replace `format-mode-line` with direct `mode-name` access; use `when` instead of `if`. Add a `nil`-safety guard to the buffer iteration loop.  
   → *fractal Cl

... (truncated)
