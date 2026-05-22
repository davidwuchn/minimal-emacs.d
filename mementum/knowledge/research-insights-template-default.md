---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 1.9/10
allium-issues: 3
allium-severity: 0.00
allium-status: ok
---

# Research Strategy: template-default

*Consolidated from 1981 experiments (19% keep rate).*

**Performance:** 385 kept / 1121 discarded / 37 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-tools-agent-validation.el` (3 kept / 5 discarded / 1 failed)
- `lisp/modules/gptel-benchmark-evolution.el` (7 kept / 18 discarded)
- `lisp/modules/gptel-tools-agent-strategy-harness.el` (2 kept / 2 discarded / 1 failed)
- `lisp/modules/gptel-benchmark-comparator.el` (2 kept / 4 discarded)
- `lisp/modules/gptel-ext-tool-confirm.el` (1 kept / 3 discarded)
- `lisp/modules/gptel-ext-abort.el` (1 kept / 7 discarded)
- `lisp/modules/gptel-ext-context.el` (13 kept / 18 discarded / 1 failed)
- `lisp/modules/gptel-ext-reasoning.el` (2 kept / 4 discarded / 4 failed)
- `lisp/modules/gptel-ext-retry.el` (17 kept / 50 discarded)
- `lisp/modules/nucleus-tools-validate.el` (3 kept / 9 discarded)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-auto-experiment--invalid-cl-return-target-in-forms, gptel-auto-experiment--invalid-cl-return-target, gptel-auto-experiment--defensive-code-removal-p, gptel-auto-experiment--diff-against-head, gptel-auto-experiment--defined-function-symbols, gptel-auto-experiment--diff-added-lines, gptel-auto-experiment--call-symbols-in-line, gptel-auto-experiment--defined-runtime-call-p, gptel-auto-experiment--call-symbols-in-forms, gptel-auto-experiment--introduced-undefined-call, gptel-auto-experiment--forward-sexp-file, gptel-auto-experiment--validate-code
requires: cl-lib, subr-x
provides: gptel-tools-agent-validation
declares: gptel-auto-workflow--read-file-contents
errors: error, error, error, error, error, error
handlers: err, err
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-auto-workflow-ontology-strategy.el` (4 discarded / 2 failed)
- `lisp/modules/gptel-tools-agent-strategy-harness.el` (2 kept / 2 discarded / 1 failed)
- `lisp/modules/gptel-ext-context.el` (13 kept / 18 discarded / 1 failed)
- `lisp/modules/gptel-benchmark-tests.el` (3 failed)
- `lisp/modules/gptel-ext-reasoning.el` (2 kept / 4 discarded / 4 failed)

## Allium Behavioral Coherence

*3 behavioral issues (severity 0.00). EXTRACTED from Allium v3 pipeline.*



## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.
