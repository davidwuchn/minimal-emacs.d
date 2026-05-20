---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 1.9/10
allium-issues: 4
allium-severity: 0.05
allium-status: ok
---

# Research Strategy: template-default

*Consolidated from 1832 experiments (19% keep rate).*

**Performance:** 357 kept / 1041 discarded / 23 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-benchmark-instincts.el` (3 kept / 6 discarded)
- `lisp/modules/gptel-benchmark-principles.el` (1 kept / 1 discarded / 2 failed)
- `lisp/modules/gptel-benchmark-core.el` (20 kept / 48 discarded / 1 failed)
- `lisp/modules/gptel-auto-workflow-strategic.el` (11 kept / 37 discarded / 3 failed)
- `lisp/modules/gptel-tools-agent.el` (61 kept / 156 discarded / 1 failed)
- `lisp/modules/gptel-ext-tool-sanitize.el` (39 kept / 72 discarded / 5 failed)
- `lisp/modules/gptel-tools-memory.el` (2 kept / 3 discarded)
- `lisp/modules/gptel-sandbox.el` (29 kept / 75 discarded)
- `lisp/modules/gptel-ext-fsm-utils.el` (34 kept / 68 discarded)
- `lisp/modules/gptel-ext-context-cache.el` (30 kept / 92 discarded)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-benchmark-instincts-compute-phi, gptel-benchmark-instincts-record, gptel-benchmark-instincts-get-accumulated, gptel-benchmark-instincts-clear-accumulator, gptel-benchmark-instincts-accumulator-size, gptel-benchmark-instincts--calculate-decay, gptel-benchmark-instincts-apply-decay, gptel-benchmark-instincts--parse-frontmatter, gptel-benchmark-instincts--parse-instincts, gptel-benchmark-instincts-get-instinct, gptel-benchmark-instincts-status, gptel-benchmark-instincts-confident-p, gptel-benchmark-instincts-format-compact, gptel-benchmark-instincts-commit-batch, gptel-benchmark-instincts--apply-updates-to-file, gptel-benchmark-instincts--get-existing-instincts, gptel-benchmark-instincts--merge-updates, gptel-benchmark-instincts--merge-eight-keys, gptel-benchmark-instincts--write-frontmatter, gptel-benchmark-instincts--format-instincts-yaml
defvars: gptel-benchmark-instincts-delta-positive, gptel-benchmark-instincts-delta-negative, gptel-benchmark-instincts-decay-rate, gptel-benchmark-instincts-phi-minimum, gptel-benchmark-instincts-evidence-threshold, gptel-benchmark-instincts-weak-threshold, gptel-benchmark-instincts-phi-max, gptel-benchmark-instincts--accumulator, gptel-benchmark-instincts-timer
requires: cl-lib
provides: gptel-benchmark-instincts
declares: gptel-mementum-weekly-job
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-benchmark-principles.el` (1 kept / 1 discarded / 2 failed)
- `lisp/modules/gptel-auto-workflow-strategic.el` (11 kept / 37 discarded / 3 failed)
- `lisp/modules/gptel-tools-agent.el` (61 kept / 156 discarded / 1 failed)
- `lisp/modules/gptel-ext-tool-sanitize.el` (39 kept / 72 discarded / 5 failed)
- `lisp/modules/gptel-tools-agent-validation.el` (1 kept / 3 discarded / 1 failed)

## Allium Behavioral Coherence

*4 behavioral issues (severity 0.05). EXTRACTED from Allium v3 pipeline.*



## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.
