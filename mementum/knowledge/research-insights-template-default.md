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

*Consolidated from 185 experiments (5% keep rate).*

**Performance:** 10 kept / 1 discarded / 21 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-tools-agent-prompt-build.el` (3 kept / 2 failed)
- `lisp/modules/gptel-auto-workflow-projects.el` (4 kept / 1 failed)
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

- `lisp/modules/gptel-auto-workflow-projects.el` (4 kept / 1 failed)
- `lisp/modules/gptel-auto-workflow-strategic.el` (4 failed)
- `lisp/modules/gptel-benchmark-subagent.el` (2 kept / 3 failed)
- `lisp/modules/gptel-tools-agent-error.el` (1 failed)
- `lisp/modules/gptel-tools-agent-prompt-build.el` (3 kept / 2 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.
