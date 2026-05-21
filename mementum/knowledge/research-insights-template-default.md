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

*Consolidated from 1891 experiments (19% keep rate).*

**Performance:** 366 kept / 1076 discarded / 27 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-tools-memory.el` (3 kept / 9 discarded)
- `lisp/modules/gptel-ext-core.el` (10 kept / 12 discarded / 1 failed)
- `lisp/modules/gptel-tools.el` (5 kept / 8 discarded)
- `lisp/modules/gptel-ext-fsm-utils.el` (37 kept / 70 discarded / 1 failed)
- `lisp/modules/gptel-tools-agent-experiment-loop.el` (1 kept / 3 discarded)
- `lisp/modules/gptel-benchmark-instincts.el` (3 kept / 6 discarded)
- `lisp/modules/gptel-benchmark-principles.el` (1 kept / 1 discarded / 2 failed)
- `lisp/modules/gptel-benchmark-core.el` (20 kept / 48 discarded / 1 failed)
- `lisp/modules/gptel-auto-workflow-strategic.el` (11 kept / 37 discarded / 3 failed)
- `lisp/modules/gptel-tools-agent.el` (61 kept / 156 discarded / 1 failed)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-tools-memory--project-root, gptel-tools-memory--invalidate-cache, gptel-tools-memory--resolve-path, gptel-tools-memory--read, gptel-tools-memory--write, gptel-tools-memory--collect-dir, gptel-tools-memory--list, gptel-tools-memory-register
defvars: gptel-tools-memory-dir, gptel-tools-memory-knowledge-dir, gptel-tools-memory--cached-root
requires: cl-lib, subr-x
provides: gptel-tools-memory
errors: error, error, error, error, error, error, error, error, error
handlers: err
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-ext-reasoning.el` (1 failed)
- `lisp/modules/gptel-ext-fsm-utils.el` (37 kept / 70 discarded / 1 failed)
- `lisp/modules/gptel-ext-core.el` (10 kept / 12 discarded / 1 failed)
- `lisp/modules/gptel-auto-workflow-git-learning.el` (2 kept / 6 discarded / 1 failed)
- `lisp/modules/gptel-benchmark-principles.el` (1 kept / 1 discarded / 2 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.
