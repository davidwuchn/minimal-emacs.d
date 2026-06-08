---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 0.5/10
allium-issues: 0
allium-severity: 0.00
allium-status: coherent
---

# Research Strategy: template-default

*Consolidated from 194 experiments (5% keep rate).*

**Performance:** 10 kept / 1 discarded / 21 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-tools-agent-prompt-build.el` (3 kept / 2 failed)
- `lisp/modules/gptel-auto-workflow-projects.el` (4 kept)
- `lisp/modules/gptel-benchmark-subagent.el` (2 kept / 3 failed)
- `lisp/modules/gptel-ext-retry.el` (1 kept)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-auto-workflow--knowledge-cache-get, gptel-auto-workflow--knowledge-cache-set, gptel-auto-workflow--knowledge-cache-invalidate, gptel-auto-workflow--knowledge-cache-stats, gptel-auto-workflow--load-token-efficiency-data, gptel-auto-workflow--adapt-prompt-compression, gptel-auto-experiment--prompt-structure-score, gptel-auto-experiment--kibcm-axis, gptel-auto-experiment--forge-fixed-point, gptel-auto-experiment--compile-score, gptel-auto-experiment--decompile-score, gptel-auto-experiment--nucleus-compiler-prompt, gptel-auto-experiment--forge-lambda-fixed-point, gptel-auto-experiment--edn-richness-score, gptel-auto-experiment--count-edn-elements, gptel-auto-experiment--use-lambda-prompts-p, gptel-auto-experiment--lambda-compress-prompt, gptel-auto-experiment--resolve-prompt, gptel-auto-experiment--allium-compiler-prompt, gptel-auto-experiment--allium-distill
defvars: gptel-ai-behaviors--current-hashtags), gptel-ai-behaviors--current-strategy), gptel-ai-behaviors--combo-hashtag), gptel-auto-experiment--suggested-workflow), gptel-auto-experiment--current-task-hint), gptel-auto-experiment--review-feedback), gptel-auto-workflow--current-strategy-name), gptel-auto-experiment--mementum-recall), gptel-auto-experiment--grader-insights), gptel-auto-experiment--executor-reasoning), gptel-task-type-model-defaults), gptel-auto-workflow-executor-rate-limit-fallbacks), gptel-backend-models), gptel-auto-workflow--skills), gptel-auto-experiment-large-target-byte-threshold), gptel-auto-workflow--last-prompt-sections), gptel-auto-workflow--current-research-context), gptel-auto-experiment-time-budget), gptel-auto-workflow-use-staging), gptel-auto-workflow--running)
requires: cl-lib, seq, subr-x, gptel-ext-backend-registry
provides: gptel-tools-agent-prompt-build
declares: gptel-auto-workflow--plist-delete-all, gptel-agent-read-file, gptel-auto-workflow--valid-strategy-name-p, gptel-auto-workflow--best-strategy-for-axis, gptel-auto-workflow-load-research-findings, gptel-benchmark--detect-task-type, gptel-backend-name, gptel-request, my/gptel-get-model-metadata, gptel-auto-workflow--current-run-id, gptel-auto-workflow--ensure-results-file, gptel-auto-workflow--make-idempotent-callback, gptel-auto-workflow--non-empty-string-p, gptel-auto-workflow--plist-get, gptel-auto-workflow--results-file-path, gptel-auto-workflow--worktree-base-root, gptel-auto-experiment--eight-keys-scores, gptel-auto-workflow--project-root, gptel-auto-workflow--persist-status, my/gptel--sanitize-for-logging
errors: Error, error, error, error, ERROR, error, error, error, error, Error, signal, error, signal, error, error, error, error, error, error, error
handlers: nil, nil, err, ..., ...), nil, err, err, err, err, err, err, err, nil, nil
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings
were misleading.

- `lisp/modules/gptel-auto-workflow-strategic.el` (4 failed)
- `lisp/modules/gptel-benchmark-subagent.el` (2 kept / 3 failed)
- `lisp/modules/gptel-tools-agent-error.el` (1 failed)
- `lisp/modules/gptel-tools-agent-prompt-build.el` (3 kept / 2 failed)
- `lisp/modules/gptel-tools-agent-experiment-core.el` (1 discarded / 6 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.






































































































































































































































































































































































































































































































































































































## Allium Behavioral Spec (auto-generated, v3)

*0 check issues (severity 0.30). EXTRACTED from distill→check pipeline.*

```allium
# Distillation: template-default Research

## Scope
- **163 experiments** across 45 targets (mostly `gptel-auto-workflow-*`, `gptel-tools-agent-*`, `gptel-ext-*`, `gptel-benchmark-*` modules, plus `staging-merge`, `staging-review`, `treesit-agent-tools-workspace`).
- Strategy: **template-default** (default-hypothesis sweep across all target surfaces).

## Surviving Hypotheses (3)

All three share a common thread: **making implicit error/failure paths explicit via sentinels and guards**, evaluated along **Axis A (error handling)** and **Axis D (safety)**.

| # | Target | Mechanism | Axes |
|---|--------|-----------|------|
| 1 | `gptel-benchmark-call-subagent-sync` | Add **timeout sentinel** distinct from `nil` so callers can disambiguate timeout from success. | A, D |
| 2 | (target obscured in source) | **Nil-guard `where`** + wrap overlay creation in `condition-case` so overlay faults don't break task execution. | A, D |
| 3 | `gptel--fsm-next` (called by `my/gptel-auto-retry`) | Wrap in `condition-case`, default to `ERRS` on invalid FSM state so retry machinery survives instead of aborting. | A, D |

## Rejected Hypotheses
- Effectively **none survived as structured content** — the rejected set is filled with `unknown` / placeholder entries. Treat the kept list as the empirical yield of the run; the discard log carries no signal.

## Synthesis

The template-default sweep converged on a **narrow but coherent cluster**: every kept hypothesis is a **defensive boundary** at a known fragility point — a synchronous subagent call that can hang, an overlay API that can throw, and an FSM transition that can be queried in an invalid state. No hypothesis proposed *new capability*; all proposed **making existing failure modes recoverable or classifiable**.

**Implication for the workstream:** the empirical bottleneck is not feature coverage but **error-path clarity at module seams**. Future experiments should pivot away from template-default toward targeted probes around (a) timeout/sentinel conventions for sync subagent calls, (b) overlay/UI-side fault isolation, and (c) FSM precondition checks in retry orchestration.

## Caveats
- One kept hypothesis (#2) lost its target identifier in transcription; verify before acting on it.
- The discard log being structurally empty is itself a signal: either rejection criteria were over-strict, or rejected entries were not promoted into the report.
```

### Check Issues

# Review of Distillation Document

Overall this is well-structured, honest about its limitations, and the synthesis is strong. A few things worth tightening:

## Factual / concrete concerns

**1. "`where`" in hypothesis #2.**
In Emacs Lisp, `where` isn't a standard function/keyword. Most likely transcription of `when` (the common guard form), or possibly a `cl-find`/predicate call where someone wrote a bareword `where` informally. Worth verifying against the source before acting on it, because the mechanism description hinges on this token.

**2. 1.8% yield isn't called out.**
163 experiments → 3 kept. That's a 98.2% rejection rate. The synthesis calls the result "narrow but coherent" without ever saying it was *also* an unusually thin one. The caveat hints at over-strict rejection criteria, but the reader has to do that arithmetic. A one-liner like "yield was ~1.8%; the cluster is coherent but rests on three observations" would calibrate expectations correctly.

**3. Axis A and Axis D are referenced but never defined.**
The reader is told every kept hypothesis scored on these two axes, with no mention of B or C. Either:
- there are only A and D in the rubric (then say so), or
- the other axes exist and were systematically empty (then say that).

As written, the gap is distracting and undermines the "coherent cluster" framing — coherence along *two* of *N* axes is a weaker claim than the document implies.

## Structural / framing

**4. "No hypothesis proposed new capability" is sli

... (truncated)
