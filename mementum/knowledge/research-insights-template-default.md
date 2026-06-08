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

*Consolidated from 61 experiments (3% keep rate).*

**Performance:** 2 kept / 0 discarded / 25 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-auto-workflow-projects.el` (2 kept / 3 failed)

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

- `lisp/modules/gptel-auto-workflow-projects.el` (2 kept / 3 failed)
- `lisp/modules/gptel-benchmark-subagent.el` (3 failed)
- `lisp/modules/gptel-tools-agent-error.el` (3 failed)
- `lisp/modules/gptel-tools-agent-prompt-build.el` (3 failed)
- `lisp/modules/gptel-auto-workflow-strategic.el` (3 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.
































































































































































































































































































































## Allium Behavioral Spec (auto-generated, v3)

*8 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Distillation

## Strategy Applied
**template-default** — generic exploratory pass over 158 experiments spanning 46 target files in the gptel/auto-workflow ecosystem. No specialized targeting; the pass surfaced one defensible signal and discarded the remainder as unverifiable.

## Surviving Hypothesis (1 / 158)

**Target:** `my/gptel-auto-retry` interaction with `gptel--fsm-next`

**Claim:** Wrapping `gptel--fsm-next` in `condition-case` defuses a latent crash path. When the FSM occupies an invalid state and cannot resolve a next-state, the bare call propagates an error that aborts the retry machinery. A `condition-case` guard lets the call safely fall through to `ERRS`, which is the original intended transition for failure handling.

**Rationale:** The FSM's recovery path is already defined (`ERRS`); the bug is not in the state machine itself but in the lack of a guard at the call site, so the original transition logic can still do its job.

## Discarded Material
- 157 hypotheses discarded as **unknown** — no surviving evidence to characterize.
- One additional fragment ("[what changes & why]") was a required-field stub rather than a hypothesis.

## Net Yield
One concrete, narrow, actionable finding: a single `condition-case` wrap around `gptel--fsm-next` at its call site in the retry path. Low blast radius, preserves existing failure semantics, addresses a real crash class rather than inventing new behavior.
```

### Check Issues

**Check Summary**

The distillation is well-structured but the lone surviving hypothesis is under-supported and possibly the wrong layer of fix. The shape of the writeup is good; the content of the finding needs more verification.

---

### What's Solid

- Epistemic honesty in the discarded material — marking as "unknown" rather than "disproven" is the right call.
- Acknowledging the required-field stub as a stub rather than a hypothesis.
- Narrow, low-blast-radius framing of the proposed change.
- Clean separation of strategy / hypothesis / rationale / yield.

---

### What's Questionable

1. **"ERRS is the original intended transition for failure handling" is an inference, not a fact.** The distillation presents it as settled, but reaching ERRS could happen via a return value (in which case `condition-case` is unnecessary), a state assignment by the caller, or a separate signal path. Without the call site in view, the mechanism is unspecified.

2. **The fix targets the symptom, not the cause.** If `gptel--fsm-next` signals on invalid states, the real question is *why* the FSM enters an invalid state. Plausible alternatives:
   - Validate state at the call site before invoking `gptel--fsm-next`
   - Have `gptel--fsm-next` return a sentinel instead of signaling
   - Add a precondition in the FSM itself
   
   The proposed fix assumes the call site is the right layer without arguing it.

3. **"Aborts the retry machinery" is unverified.** If the retry loop already has error handling, the 

... (truncated)
