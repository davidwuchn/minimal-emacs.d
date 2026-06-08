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

*3 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Distillation

## Scope
163 experiments across 45 gptel modules using the `template-default` research strategy. The target surface spans auto-workflow orchestration, tools-agent runtime/staging/error paths, extensions (backend registry, circuit breaker, retry, tool permits, core), benchmarks (principles, core, subagent), and supporting infrastructure (knowledge reasoning, monitoring, self-audit, CQ evolution, mementum, staging-merge/review).

## Substantive Finding (1 kept hypothesis)

**Defensive FSM guard in `my/gptel-auto-retry`.** Wrapping the call to `gptel--fsm-next` in a `condition-case` so that an unresolvable next-state condition yields `ERRS` rather than signaling:

- Protects the retry loop from being torn down by an upstream FSM invariant violation.
- Routes the failure back through the normal transition path, preserving whatever logging/notification the `ERRS` arm already implements.
- Costs nothing on the happy path (a `condition-case` with no matching condition is effectively a no-op besides the tag form).

That is the only hypothesis the harness actually retained evidence for.

## Discarded / Unknown
All 3 discard slots are `unknown` — the first is a verbatim template stub ("[what changes & why]" (NEVER leave blank)), and the next two are unpopulated placeholders. No hypotheses were explicitly rejected with reason; effectively nothing was ruled out.

## Gaps in the run

1. **Hypothesis coverage is near-zero.** Out of 163 experiments, the template produced one confirmed hypothesis and zero reasoned rejections. This is a template-fill failure, not a signal about the codebase — the targets were not interrogated.
2. **No kept hypotheses for any of the 45 targets except the FSM/`auto-retry` adjacency.** The auto-workflow production/evolution/knowledge-reasoning/ontology-router/monitoring-agent modules, the tools-agent staging-merge/runtime/validation/error harness, and the extensions (circuit breaker, retry, tool permits, backend registry) were not examined in any captured result.
3. **No cross-target synthesis.** Nothing links, e.g., `gptel-ext-retry.el` to `my/gptel-auto-retry`, or the staging-merge/approval-queue/decision-classification trio. The single kept finding sits in isolation.
4. **No `[what changes & why]` entry was produced** — the template's required change-rationale field is empty across the board.

## Recommended next action

The run should be re-run with the hypothesis-extraction template fields actually populated, or the existing artifacts should be back-filled. The `template-default` strategy is clearly not producing output for this corpus. A narrower scope (e.g., the auto-retry / ext-retry / circuit-breaker cluster, or the tools-agent staging + validation + error trio) would likely yield a denser, more useful kept-hypothesis set than another full-corpus sweep with the same template.
```

### Check Issues

**Check on the distillation — verdict: structurally sound, but a few claims need tightening before you act on it.**

### Correct as written
- The 1-of-163 framing is fair *if* 163 is the experiment count, not the hypothesis count. The report blurs this — see below.
- "Template-fill failure, not a signal about the codebase" is the right read. A single surfaced hypothesis with three empty discard slots is exactly what a misconfigured template produces; it's not evidence the corpus is empty.
- The four gap items are well-stated and distinct. Each points at a different failure mode (coverage, scope, synthesis, required-field).
- The recommended next action is concrete: either back-fill the existing artifacts or pick a narrower cluster. The two suggested clusters (retry/circuit-breaker triad, or tools-agent staging+validation+error) are reasonable choices.

### Needs qualification

1. **"1 / 163" denominator.** "Out of 163 experiments, … one confirmed hypothesis and zero reasoned rejections" reads as if 163 is the hypothesis count. If 163 is the *run* count, the ratio is fine; if 163 is the *hypotheses generated* count, that's a much harsher statement and you should say so. Clarify which it is. Same concern applies to "no kept hypotheses for any of the 45 targets" — that should be "no kept hypotheses *captured*," since a broken template can't prove absence.

2. **"Costs nothing on the happy path."** Slight overstatement. `condition-case` is a cheap form (basically an `unwind-pr

... (truncated)
