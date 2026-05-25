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

*Consolidated from 1337 experiments (19% keep rate).*

**Performance:** 252 kept / 688 discarded / 100 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-tools-agent-runtime.el` (2 kept / 4 discarded / 2 failed)
- `lisp/modules/gptel-benchmark-core.el` (22 kept / 32 discarded / 7 failed)
- `lisp/modules/gptel-ext-tool-permits.el` (3 kept / 2 discarded)
- `lisp/modules/gptel-benchmark-comparator.el` (3 kept / 14 discarded / 1 failed)
- `lisp/modules/gptel-tools-memory.el` (12 kept / 20 discarded)
- `lisp/modules/gptel-workflow-benchmark.el` (1 kept / 6 discarded / 6 failed)
- `lisp/modules/gptel-benchmark-principles.el` (5 kept / 4 discarded / 1 failed)
- `lisp/modules/gptel-tools-agent-staging-baseline.el` (2 kept / 5 discarded)
- `lisp/modules/gptel-ext-abort.el` (2 kept / 4 discarded / 2 failed)
- `lisp/modules/nucleus-tools-validate.el` (5 kept / 10 discarded / 1 failed)

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

- `lisp/modules/gptel-tools-agent-runtime.el` (2 kept / 4 discarded / 2 failed)
- `lisp/modules/gptel-benchmark-core.el` (22 kept / 32 discarded / 7 failed)
- `lisp/modules/gptel-tools-agent-subagent.el` (1 failed)
- `lisp/modules/gptel-workflow-benchmark.el` (1 kept / 6 discarded / 6 failed)
- `lisp/modules/nucleus-tools.el` (6 kept / 14 discarded / 3 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.


## Allium Behavioral Spec (auto-generated, v3)

*0 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
nil
```

