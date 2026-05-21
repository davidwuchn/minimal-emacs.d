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

*Consolidated from 1212 experiments (19% keep rate).*

**Performance:** 232 kept / 650 discarded / 90 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-tools-agent-runtime.el` (1 kept / 3 discarded)
- `lisp/modules/gptel-ext-abort.el` (2 kept / 4 discarded / 2 failed)
- `lisp/modules/nucleus-tools-validate.el` (5 kept / 10 discarded / 1 failed)
- `lisp/modules/gptel-benchmark-comparator.el` (2 kept / 13 discarded / 1 failed)
- `lisp/modules/gptel-tools-memory.el` (6 kept / 7 discarded)
- `lisp/modules/gptel-ext-context.el` (7 kept / 14 discarded)
- `lisp/modules/nucleus-tools.el` (6 kept / 12 discarded / 3 failed)
- `lisp/modules/gptel-ext-fsm-utils.el` (9 kept / 23 discarded / 6 failed)
- `lisp/modules/gptel-benchmark-evolution.el` (7 kept / 14 discarded / 2 failed)
- `lisp/modules/gptel-benchmark-principles.el` (3 kept / 3 discarded / 1 failed)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-auto-workflow--path-exists-or-symlink-p, gptel-auto-workflow--safe-truename, gptel-auto-workflow--link-shared-runtime-path, gptel-auto-workflow--seed-worktree-runtime-var
requires: cl-lib
provides: gptel-tools-agent-runtime
declares: gptel-auto-workflow--worktree-base-root, gptel-auto-workflow--worktree-base-repo-root
errors: error
handlers: nil
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/nucleus-tools.el` (6 kept / 12 discarded / 3 failed)
- `lisp/modules/nucleus-tools-validate.el` (5 kept / 10 discarded / 1 failed)
- `lisp/modules/gptel-tools-agent.el` (8 kept / 22 discarded / 4 failed)
- `lisp/modules/gptel-benchmark-core.el` (17 kept / 25 discarded / 5 failed)
- `lisp/modules/gptel-ext-fsm-utils.el` (9 kept / 23 discarded / 6 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.
