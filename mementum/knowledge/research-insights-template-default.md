---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 2.1/10
allium-issues: 0
allium-severity: 0.00
allium-status: coherent
---

# Research Strategy: template-default

*Consolidated from 1113 experiments (21% keep rate).*

**Performance:** 234 kept / 586 discarded / 36 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-benchmark-analysis.el` (1 kept / 2 discarded)
- `lisp/modules/gptel-ext-abort.el` (3 kept / 3 discarded / 1 failed)
- `lisp/modules/gptel-auto-workflow-mementum.el` (1 kept / 1 discarded)
- `lisp/modules/gptel-benchmark-principles.el` (2 kept / 3 discarded / 1 failed)
- `lisp/modules/standalone-research.el` (1 kept / 3 discarded)
- `lisp/modules/gptel-tools-agent-experiment-loop.el` (5 kept / 6 discarded)
- `lisp/modules/gptel-auto-workflow-research-benchmark.el` (2 kept / 2 discarded)
- `lisp/modules/gptel-auto-workflow-strategic.el` (15 kept / 35 discarded / 3 failed)
- `lisp/modules/gptel-tools-memory.el` (2 kept / 6 discarded / 1 failed)
- `lisp/modules/gptel-agent-loop.el` (30 kept / 43 discarded)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-benchmark-analyze-results, gptel-benchmark--parse-analysis-result, gptel-benchmark--find-tests-by-predicate, gptel-benchmark--group-by-test-id, gptel-benchmark--result-passed-p, gptel-benchmark--flaky-test-p, gptel-benchmark-find-flaky-tests, gptel-benchmark--non-discriminating-p, gptel-benchmark-find-non-discriminating, gptel-benchmark--systematic-failure-p, gptel-benchmark-find-systematic-failures, gptel-benchmark-generate-summary, gptel-benchmark-generate-improvement-plan, gptel-benchmark-assess-priority
requires: json, cl-lib, gptel-benchmark-core
provides: gptel-benchmark-analysis
declares: gptel-agent--task
errors: error, error
handlers: nil
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-benchmark-principles.el` (2 kept / 3 discarded / 1 failed)
- `lisp/modules/gptel-ext-core.el` (1 kept / 10 discarded / 1 failed)
- `lisp/modules/gptel-tools-memory.el` (2 kept / 6 discarded / 1 failed)
- `lisp/modules/gptel-ext-abort.el` (3 kept / 3 discarded / 1 failed)
- `lisp/modules/gptel-tools-agent-runtime.el` (1 kept / 7 discarded / 1 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.
