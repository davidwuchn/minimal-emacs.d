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

*Consolidated from 1851 experiments (19% keep rate).*

**Performance:** 359 kept / 1049 discarded / 25 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-ext-core.el` (9 kept / 9 discarded / 1 failed)
- `lisp/modules/gptel-ext-fsm-utils.el` (35 kept / 69 discarded)
- `lisp/modules/gptel-benchmark-instincts.el` (3 kept / 6 discarded)
- `lisp/modules/gptel-benchmark-principles.el` (1 kept / 1 discarded / 2 failed)
- `lisp/modules/gptel-benchmark-core.el` (20 kept / 48 discarded / 1 failed)
- `lisp/modules/gptel-auto-workflow-strategic.el` (11 kept / 37 discarded / 3 failed)
- `lisp/modules/gptel-tools-agent.el` (61 kept / 156 discarded / 1 failed)
- `lisp/modules/gptel-ext-tool-sanitize.el` (39 kept / 72 discarded / 5 failed)
- `lisp/modules/gptel-tools-memory.el` (2 kept / 5 discarded)
- `lisp/modules/gptel-sandbox.el` (29 kept / 75 discarded)

### Structure (deterministic scan)

```elisp-structure
defuns: my/gptel-temp-dir, my/gptel-make-temp-file, my/gptel--file-binary-p-fix, my/gptel--apply-plain-model, my/gptel--mode-hook-setup, my/gptel--set-default-directory-to-project-root, my/gptel--known-tool-names, my/gptel--preset-tool-names, my/gptel-audit-preset-tools, my/gptel--after-apply-preset, my/gptel--char-problematic-p, my/gptel--sanitize-string-for-json, my/gptel--sanitize-tool-type-symbols, my/gptel--sanitize-type-symbol, my/gptel--sanitize-tool-props, my/gptel--pre-serialize-sanitize-messages, my/gptel--sanitize-multimodal-content
defvars: gptel--openrouter), gptel--minimax), gptel--moonshot), gptel--cf-gateway), my/gptel--in-subagent-task), my/gptel-plain-model
requires: cl-lib, subr-x, project, gptel, gptel-request, gptel-openai
provides: gptel-ext-core
errors: error, error, error
advised: gptel--file-binary-p, gptel--apply-preset, gptel-curl--get-args
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-ext-core.el` (9 kept / 9 discarded / 1 failed)
- `lisp/modules/gptel-auto-workflow-git-learning.el` (2 kept / 6 discarded / 1 failed)
- `lisp/modules/gptel-benchmark-principles.el` (1 kept / 1 discarded / 2 failed)
- `lisp/modules/gptel-auto-workflow-strategic.el` (11 kept / 37 discarded / 3 failed)
- `lisp/modules/gptel-tools-agent.el` (61 kept / 156 discarded / 1 failed)

## Allium Behavioral Coherence

*3 behavioral issues (severity 0.00). EXTRACTED from Allium v3 pipeline.*



## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.
