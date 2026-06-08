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

*Consolidated from 67 experiments (3% keep rate).*

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

*5 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Distilled Research Summary

## Scope
- **Strategy:** template-default
- **Experiments:** 163
- **Targets:** 45 Emacs Lisp modules in the gptel project (covering auto-workflow, tools-agent, ext, benchmark, and staging subsystems)

## Outcome

### Kept Hypotheses (1)
**Hypothesis:** Wrapping `gptel--fsm-next` in `condition-case` prevents a crash in `my/gptel-auto-retry` when the FSM is in an invalid state.

**Mechanism:**
- Without guard → invalid FSM state causes the error to propagate and abort the retry machinery
- With `condition-case` → failure is caught and defaulted to `ERRS`, allowing the original transition path to handle the failure gracefully

**Confidence signal:** This is the only hypothesis that survived filtering — suggesting the FSM transition in the retry loop is the most well-understood or well-evidenced change in the experiment set.

### Discarded Hypotheses
- Effectively **null** — all entries are either blank or marked `unknown`
- Indicates the research strategy did not produce or retain alternative working hypotheses for the remaining targets

## Interpretation
The "template-default" strategy yielded **sparse signal**:
- High experiment count (163) but very low hypothesis retention rate (~1/45 targets = ~2%)
- The single kept hypothesis targets a **defensive programming pattern** (exception guarding around FSM transitions) rather than a feature addition
- The bulk of targets produced no actionable hypothesis — likely because template-default is a conservative strategy that only surfaces changes with strong error-condition evidence

## Recommendation
If broader coverage is needed, consider:
1. Re-running with a less conservative strategy template
2. Investigating why 44/45 targets yielded `unknown` — possible template/scope mismatch
3. Validating the lone kept hypothesis (FSM `condition-case` guard) before committing to it as the sole output
```

### Check Issues

# Review of the Distilled Research Summary

## ✅ Internally Consistent

- **Arithmetic**: 1 kept / 45 targets = 2.2% — matches the stated "~2%"
- **Narrative consistency**: The "1 kept vs. effectively null" framing aligns across the Outcome, Interpretation, and Recommendation sections
- **Self-honesty**: The summary appropriately flags its own sparsity rather than overstating the single kept result

## 🔍 Technical Claims Worth Verifying

The kept hypothesis makes three specific technical claims. I can check two of them; the third requires the source.

| Claim | Verifiable? | Status |
|---|---|---|
| `condition-case` is the standard Emacs Lisp error-handling form | Yes | ✅ Correct |
| Wrapping an invalid-state call in `condition-case` to default to an error state is a valid defensive pattern | Yes | ✅ Correct conceptually |
| `gptel--fsm-next` exists as the FSM transition entry point and `ERRS` is a valid state in `my/gptel-auto-retry` | **No — requires source** | ⚠️ Unverified |

**Specific concern with terminology**: In gptel's actual FSM, the error-related state is conventionally spelled `erros` (without the trailing `s`) — e.g., in the `gptel-request` state machine, the `:error` / `erros` handling around tools. If your summary says `ERRS`, double-check against the source — `ERRS` with two S's may be a transcription artifact or a state in *your* `my/gptel-auto-retry` layer, not in core gptel. This matters because the report implicitly treats it as a gptel-internal mechanism

... (truncated)
