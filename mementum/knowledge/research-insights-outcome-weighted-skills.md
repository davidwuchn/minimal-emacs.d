---
title: Research Insights - outcome-weighted-skills
status: active
category: knowledge
tags: [research, auto-workflow, outcome-weighted-skills]
insight-quality: 5.0/10
---

# Research Strategy: outcome-weighted-skills

*Consolidated from 4 experiments (50% keep rate).*

**Performance:** 2 kept / 1 discarded / 1 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-benchmark-principles.el` (2 kept / 1 discarded)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-benchmark--load-keys-from-skill, gptel-benchmark-eight-keys-criteria, gptel-benchmark--get-key-property, gptel-benchmark-eight-keys-signals, gptel-benchmark-eight-keys-anti-patterns, gptel-benchmark-eight-keys-element, gptel-benchmark--detect-task-type, gptel-benchmark-eight-keys-score, gptel-benchmark-eight-keys-summary, gptel-benchmark-eight-keys-weakest, gptel-benchmark-eight-keys-weakest-with-signals, gptel-benchmark--score-signals, gptel-benchmark--score-anti-patterns, gptel-benchmark-eight-keys-violations, gptel-benchmark-element-info, gptel-benchmark-element-generates, gptel-benchmark-element-controls, gptel-benchmark-element-controlled-by, gptel-benchmark-element-generated-by, gptel-benchmark-vsm-to-element
defvars: gptel-benchmark-eight-keys-weights, gptel-benchmark--key-property-cache
requires: cl-lib
provides: gptel-benchmark-principles
errors: error, error, error, error, error, signal, signal, error
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-tools-agent-main.el` (1 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy is effective.** Continue using it.
- Consider expanding the grep patterns to find similar issues.
