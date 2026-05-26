---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 2.1/10
allium-issues: 4
allium-severity: 0.00
allium-status: ok
---

# Research Strategy: template-default

*Consolidated from 1142 experiments (21% keep rate).*

**Performance:** 236 kept / 588 discarded / 36 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/strategic-daemon-functions.el` (5 kept / 2 discarded / 1 failed)
- `lisp/modules/gptel-benchmark-analysis.el` (1 kept / 2 discarded)
- `lisp/modules/gptel-ext-abort.el` (3 kept / 3 discarded / 1 failed)
- `lisp/modules/gptel-auto-workflow-mementum.el` (1 kept / 1 discarded)
- `lisp/modules/gptel-benchmark-principles.el` (2 kept / 3 discarded / 1 failed)
- `lisp/modules/standalone-research.el` (1 kept / 3 discarded)
- `lisp/modules/gptel-tools-agent-experiment-loop.el` (5 kept / 6 discarded)
- `lisp/modules/gptel-auto-workflow-research-benchmark.el` (2 kept / 2 discarded)
- `lisp/modules/gptel-auto-workflow-strategic.el` (15 kept / 35 discarded / 3 failed)
- `lisp/modules/gptel-tools-memory.el` (2 kept / 6 discarded / 1 failed)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-auto-workflow--autotts-root, gptel-auto-workflow--autotts-file, gptel-auto-workflow--load-evolved-controller-config, gptel-auto-workflow--branch-pool-init, gptel-auto-workflow--branch-pool-active-count, gptel-auto-workflow--branch-pool-add, gptel-auto-workflow--branch-pool-remove, gptel-auto-workflow--branch-pool-get-best, gptel-auto-workflow--branch-pool-get-deviant, gptel-auto-workflow--branch-pool-stagnation-p, gptel-auto-workflow--branch-pool-widen, gptel-auto-workflow--research-beta-schedule, gptel-auto-workflow--update-research-ema, gptel-auto-workflow--research-ema-delta, gptel-auto-workflow--record-research-trace, gptel-auto-workflow--reset-research-ema, gptel-auto-workflow--load-statistical-model, gptel-auto-workflow--load-researcher-feedback, gptel-auto-workflow--load-skill-topic-priors, gptel-auto-workflow--load-autotts-controller
defvars: gptel-auto-workflow--research-accumulated-findings), gptel-auto-workflow--research-total-tokens), gptel-auto-workflow--research-current-turn), gptel-auto-workflow--research-prompt), gptel-auto-workflow--research-controller-config), gptel-auto-workflow--current-research-context), gptel-auto-workflow--research-beta, gptel-auto-workflow--research-ema-conf, gptel-auto-workflow--research-ema-history, gptel-auto-workflow--research-ema-alpha, gptel-auto-workflow--research-ema-window, gptel-auto-workflow--controller-decision-history, gptel-auto-workflow--controller-doom-loop-threshold, gptel-auto-workflow--research-trace-log, gptel-auto-workflow--branch-pool, gptel-auto-workflow--branch-pool-max, gptel-auto-workflow--branch-id-counter, gptel-auto-workflow--source-effectiveness-table, gptel-auto-workflow--research-params-file
requires: cl-lib, json, subr-x
provides: strategic-daemon-functions
declares: gptel-sandbox--eval-expr, gptel-auto-workflow--normalize-response, gptel-auto-workflow--research-has-external-content-p, gptel-auto-workflow--research-error-p, gptel-auto-workflow--local-research-patterns, gptel-auto-workflow--estimate-confidence, gptel-auto-workflow--log-research-step, gptel-auto-workflow--format-research-strategy-prompt, gptel-auto-workflow--save-research-trace, gptel-auto-workflow--digest-research-findings, gptel-auto-workflow--statistical-prob-kept, gptel-benchmark-call-subagent
errors: error, error, error, signal
handlers: err, err, err, nil, err, err
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-benchmark-principles.el` (2 kept / 3 discarded / 1 failed)
- `lisp/modules/gptel-ext-core.el` (1 kept / 10 discarded / 1 failed)
- `lisp/modules/gptel-tools-memory.el` (2 kept / 6 discarded / 1 failed)
- `lisp/modules/gptel-ext-abort.el` (3 kept / 3 discarded / 1 failed)
- `lisp/modules/gptel-tools-agent-runtime.el` (1 kept / 7 discarded / 1 failed)

## Allium Behavioral Coherence

*4 behavioral issues (severity 0.00). EXTRACTED from Allium v3 pipeline.*



## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.
