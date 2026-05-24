---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 1.9/10
allium-issues: 0
allium-severity: 0.00
allium-status: coherent
---

# Research Strategy: template-default

*Consolidated from 1294 experiments (19% keep rate).*

**Performance:** 246 kept / 682 discarded / 95 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-benchmark-comparator.el` (3 kept / 14 discarded / 1 failed)
- `lisp/modules/gptel-tools-memory.el` (12 kept / 18 discarded)
- `lisp/modules/gptel-workflow-benchmark.el` (1 kept / 6 discarded / 6 failed)
- `lisp/modules/gptel-benchmark-core.el` (20 kept / 31 discarded / 5 failed)
- `lisp/modules/gptel-benchmark-principles.el` (5 kept / 4 discarded / 1 failed)
- `lisp/modules/gptel-tools-agent-staging-baseline.el` (2 kept / 5 discarded)
- `lisp/modules/gptel-tools-agent-runtime.el` (1 kept / 3 discarded)
- `lisp/modules/gptel-ext-abort.el` (2 kept / 4 discarded / 2 failed)
- `lisp/modules/nucleus-tools-validate.el` (5 kept / 10 discarded / 1 failed)
- `lisp/modules/gptel-ext-context.el` (7 kept / 14 discarded)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-benchmark--cache-get, gptel-benchmark--require-valid-string, gptel-benchmark--require-valid-name, gptel-benchmark--require-valid-version, gptel-benchmark--cache-put, gptel-benchmark--clear-result-cache, gptel-benchmark-compare-file-versions, gptel-benchmark-baseline-file-compare, gptel-benchmark--get-trend-summary, gptel-benchmark-version-trend, gptel-benchmark-compare-summaries, gptel-benchmark-load-result, gptel-benchmark--read-version-file, gptel-benchmark-current-version, gptel-benchmark-baseline-version, gptel-benchmark-get-file, gptel-benchmark--scan-versions-from-dir, gptel-benchmark-get-all-versions
defvars: gptel-benchmark-result-cache
requires: json, cl-lib, gptel-benchmark-core
provides: gptel-benchmark-comparator
declares: cl-last
errors: Signal, error, signal, Signal, Signal, signal, signal, signal, signal, signal, signal, signal, signal, signal, signal, signal
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-workflow-benchmark.el` (1 kept / 6 discarded / 6 failed)
- `lisp/modules/nucleus-tools.el` (6 kept / 14 discarded / 3 failed)
- `lisp/modules/nucleus-tools-validate.el` (5 kept / 10 discarded / 1 failed)
- `lisp/modules/gptel-tools-agent.el` (8 kept / 22 discarded / 4 failed)
- `lisp/modules/gptel-benchmark-core.el` (20 kept / 31 discarded / 5 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.


## Allium Behavioral Spec (auto-generated, v3)

*0 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
nil
```

