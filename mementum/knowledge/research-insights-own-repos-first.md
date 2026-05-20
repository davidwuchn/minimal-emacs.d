---
title: Research Insights - own-repos-first
status: active
category: knowledge
tags: [research, auto-workflow, own-repos-first]
insight-quality: 1.2/10
---

# Research Strategy: own-repos-first

*Consolidated from 51 experiments (12% keep rate).*

**Performance:** 6 kept / 26 discarded / 8 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-ext-fsm-utils.el` (4 kept / 6 discarded / 2 failed)
- `lisp/modules/gptel-agent-loop.el` (1 kept / 3 discarded)
- `lisp/modules/gptel-sandbox.el` (1 kept / 5 discarded / 1 failed)

### Structure (deterministic scan)

```elisp-structure
defuns: my/gptel--fsm-generate-id, my/gptel--fsm-register, my/gptel--fsm-unregister, my/gptel--fsm-get-by-id, my/gptel--fsm-get-id, my/gptel--fsm-predicate-resolve, my/gptel--fsm-p, my/gptel--fsm-valid-p, my/gptel--coerce-fsm, my/gptel--coerce-fsm-with-context, my/gptel--fsm-traverse, my/gptel--fsm-collect-list, my/gptel--collect-all-fsms, my/gptel--fsm-count, my/gptel--fsm-depth, my/gptel--fsm-id-valid-p, my/gptel--fsm-registry-validate
defvars: my/gptel--fsm-registry, my/gptel--fsm-id-counter, my/gptel--fsm-predicate-fn, my/gptel--fsm-id-regexp
requires: gptel, cl-lib
provides: gptel-ext-fsm-utils
errors: error, error, error, error, error, error, error, error, error, error, error, error, error
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-tools-agent-git.el` (2 discarded / 2 failed)
- `lisp/modules/gptel-ext-reasoning.el` (2 discarded / 1 failed)
- `lisp/modules/gptel-benchmark-memory.el` (1 discarded / 2 failed)
- `lisp/modules/gptel-ext-fsm-utils.el` (4 kept / 6 discarded / 2 failed)
- `lisp/modules/gptel-sandbox.el` (1 kept / 5 discarded / 1 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.
