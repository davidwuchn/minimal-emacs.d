---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 1.8/10
allium-issues: 0
allium-severity: 0.00
allium-status: coherent
---

# Research Strategy: template-default

*Consolidated from 1380 experiments (18% keep rate).*

**Performance:** 254 kept / 698 discarded / 102 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-tools-agent-prompt-build.el` (1 kept / 3 discarded)
- `lisp/modules/gptel-auto-workflow-projects.el` (12 kept / 22 discarded / 2 failed)
- `lisp/modules/gptel-tools-agent-runtime.el` (2 kept / 4 discarded / 2 failed)
- `lisp/modules/gptel-benchmark-core.el` (22 kept / 32 discarded / 7 failed)
- `lisp/modules/gptel-ext-tool-permits.el` (3 kept / 2 discarded)
- `lisp/modules/gptel-benchmark-comparator.el` (3 kept / 14 discarded / 1 failed)
- `lisp/modules/gptel-tools-memory.el` (12 kept / 20 discarded)
- `lisp/modules/gptel-workflow-benchmark.el` (1 kept / 6 discarded / 6 failed)
- `lisp/modules/gptel-benchmark-principles.el` (5 kept / 4 discarded / 1 failed)
- `lisp/modules/gptel-tools-agent-staging-baseline.el` (2 kept / 5 discarded)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-auto-workflow--knowledge-cache-get, gptel-auto-workflow--knowledge-cache-set, gptel-auto-workflow--knowledge-cache-invalidate, gptel-auto-workflow--knowledge-cache-stats, gptel-auto-workflow--load-token-efficiency-data, gptel-auto-workflow--adapt-prompt-compression, gptel-auto-experiment--prompt-structure-score, gptel-auto-experiment--kibcm-axis, gptel-auto-experiment--forge-fixed-point, gptel-auto-experiment--compile-score, gptel-auto-experiment--decompile-score, gptel-auto-experiment--nucleus-compiler-prompt, gptel-auto-experiment--forge-lambda-fixed-point, gptel-auto-experiment--edn-richness-score, gptel-auto-experiment--count-edn-elements, gptel-auto-experiment--allium-compiler-prompt, gptel-auto-experiment--allium-distill, gptel-auto-experiment--allium-check, gptel-auto-experiment--allium-decompile, gptel-auto-experiment--allium-issues-count
defvars: gptel-auto-workflow--skills), gptel-auto-experiment-large-target-byte-threshold), gptel-auto-workflow--last-prompt-sections), gptel-auto-workflow--current-research-context), gptel-auto-experiment-time-budget), gptel-auto-workflow-use-staging), gptel-auto-workflow--running), gptel-auto-workflow--stats), gptel-auto-experiment-validation-retry-active-grace), gptel-auto-workflow--legacy-validation-retry-active-grace), gptel-auto-workflow--current-validation-retry-active-grace), my/gptel-subagent-stream), gptel-auto-workflow--knowledge-cache, gptel-auto-workflow--knowledge-cache-max-age, gptel-auto-workflow--topic-knowledge-max-chars, gptel-auto-workflow--ab-test-sections, gptel-auto-workflow--ab-test-omit-rate, gptel-auto-workflow--ab-test-min-samples, gptel-auto-workflow--selected-skill-variant, gptel-auto-workflow--current-experiment-axis
requires: cl-lib, seq, subr-x
provides: gptel-tools-agent-prompt-build
declares: gptel-agent-read-file, gptel-auto-workflow--valid-strategy-name-p, gptel-auto-workflow-load-research-findings, gptel-benchmark--detect-task-type, my/gptel-get-model-metadata, gptel-auto-workflow--current-run-id, gptel-auto-workflow--ensure-results-file, gptel-auto-workflow--make-idempotent-callback, gptel-auto-workflow--non-empty-string-p, gptel-auto-workflow--plist-get, gptel-auto-workflow--results-file-path, gptel-auto-workflow--worktree-base-root, gptel-auto-experiment--eight-keys-scores, gptel-auto-workflow--project-root, gptel-auto-workflow--persist-status, my/gptel--sanitize-for-logging, gptel-auto-workflow--extract-mutation-templates, gptel-auto-workflow--format-weakest-keys, gptel-auto-workflow-skill-suggest-hypothesis, gptel-auto-experiment--inspection-thrash-result-p
errors: Error, error, error, Error, error, error, error, error, error, error, error, Error, signal, signal, error, error
handlers: nil, nil, err, err, err, err, err, err, nil
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-auto-workflow-strategic.el` (14 kept / 35 discarded / 8 failed)
- `lisp/modules/gptel-auto-workflow-evolution.el` (1 failed)
- `lisp/modules/gptel-tools-agent-runtime.el` (2 kept / 4 discarded / 2 failed)
- `lisp/modules/gptel-benchmark-core.el` (22 kept / 32 discarded / 7 failed)
- `lisp/modules/gptel-tools-agent-subagent.el` (1 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.
