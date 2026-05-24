---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 2.1/10
allium-issues: 5
allium-severity: 0.05
allium-status: ok
---

# Research Strategy: template-default

*Consolidated from 1081 experiments (21% keep rate).*

**Performance:** 229 kept / 578 discarded / 34 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/standalone-research.el` (1 kept / 3 discarded)
- `lisp/modules/gptel-tools-agent-experiment-loop.el` (5 kept / 6 discarded)
- `lisp/modules/gptel-auto-workflow-research-benchmark.el` (2 kept / 2 discarded)
- `lisp/modules/gptel-auto-workflow-strategic.el` (15 kept / 35 discarded / 3 failed)
- `lisp/modules/gptel-ext-abort.el` (1 kept / 1 discarded / 1 failed)
- `lisp/modules/gptel-tools-memory.el` (2 kept / 6 discarded / 1 failed)
- `lisp/modules/gptel-agent-loop.el` (30 kept / 43 discarded)
- `lisp/modules/gptel-benchmark-comparator.el` (1 kept)
- `lisp/modules/gptel-ext-context.el` (4 kept / 14 discarded)
- `lisp/modules/gptel-ext-fsm-utils.el` (7 kept / 12 discarded / 2 failed)

### Structure (deterministic scan)

```elisp-structure
defuns: slr--root, slr--estimate-confidence, slr--save-trace, slr--record-context, slr--load-skill, slr--save-findings, slr--usable-findings-p, slr--local-fallback-findings, slr--finish-single-turn, slr--run-single-turn, slr-run-research, slr--build-prompt
defvars: gptel-auto-workflow--current-research-context), gptel-auto-workflow--research-in-progress)
requires: json
provides: standalone-research
declares: gptel-benchmark-call-subagent
errors: signal
handlers: err, err, err
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-tools-memory.el` (2 kept / 6 discarded / 1 failed)
- `lisp/modules/gptel-ext-abort.el` (1 kept / 1 discarded / 1 failed)
- `lisp/modules/gptel-tools-agent-runtime.el` (1 kept / 7 discarded / 1 failed)
- `lisp/modules/strategic-daemon-functions.el` (3 kept / 1 failed)
- `lisp/modules/gptel-ext-fsm-utils.el` (7 kept / 12 discarded / 2 failed)

## Allium Behavioral Coherence

*5 behavioral issues (severity 0.05). EXTRACTED from Allium v3 pipeline.*



## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.


































## Allium Behavioral Spec (auto-generated, v3)

*0 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
nil
```

