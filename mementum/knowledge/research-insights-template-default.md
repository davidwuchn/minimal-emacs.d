---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 1.9/10
allium-issues: 4
allium-severity: 0.00
allium-status: ok
---

# Research Strategy: template-default

*Consolidated from 1267 experiments (19% keep rate).*

**Performance:** 244 kept / 674 discarded / 95 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-workflow-benchmark.el` (1 kept / 6 discarded / 6 failed)
- `lisp/modules/gptel-benchmark-core.el` (20 kept / 31 discarded / 5 failed)
- `lisp/modules/gptel-tools-memory.el` (11 kept / 17 discarded)
- `lisp/modules/gptel-benchmark-principles.el` (5 kept / 4 discarded / 1 failed)
- `lisp/modules/gptel-tools-agent-staging-baseline.el` (2 kept / 5 discarded)
- `lisp/modules/gptel-tools-agent-runtime.el` (1 kept / 3 discarded)
- `lisp/modules/gptel-ext-abort.el` (2 kept / 4 discarded / 2 failed)
- `lisp/modules/nucleus-tools-validate.el` (5 kept / 10 discarded / 1 failed)
- `lisp/modules/gptel-benchmark-comparator.el` (2 kept / 13 discarded / 1 failed)
- `lisp/modules/gptel-ext-context.el` (7 kept / 14 discarded)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-workflow--result-scores, gptel-workflow--tool-calls-list, gptel-workflow--tool-names, gptel-workflow--phase-active-p, gptel-workflow-load-tests, gptel-workflow--normalize-test, gptel-workflow--read-json, gptel-workflow--collect-tool-call, gptel-workflow--setup-hooks, gptel-workflow--teardown-hooks, gptel-workflow--tool-use-advice, gptel-workflow-retrieve-memories, gptel-workflow--format-memories-for-context, gptel-workflow-detect-phases, gptel-workflow--detect-p1, gptel-workflow--detect-p2, gptel-workflow--detect-p3, gptel-workflow--agent-type, gptel-workflow-run-test, gptel-workflow-score
defvars: gptel-agent-loop--state), gptel-benchmark-eight-keys-definitions), gptel-workflow-tests-dir, gptel-workflow-results-dir, gptel-workflow-default-timeout, gptel-workflow--current-run, gptel-workflow--runs, gptel-workflow--tool-call-hook, gptel-workflow-benchmark--cancelled, gptel-workflow-feedback-file
requires: cl-lib, json, subr-x
provides: gptel-workflow-benchmark
declares: gptel-agent-loop--task-continuation-count, gptel-agent-loop--task-step-count, gptel-agent--task, gptel-benchmark-eight-keys-score, gptel-benchmark-memory-search, gptel-benchmark-memory-read
errors: error, error, error
handlers: err, err, nil, nil, nil, nil
advised: gptel--handle-tool-use
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-workflow-benchmark.el` (1 kept / 6 discarded / 6 failed)
- `lisp/modules/nucleus-tools.el` (6 kept / 14 discarded / 3 failed)
- `lisp/modules/nucleus-tools-validate.el` (5 kept / 10 discarded / 1 failed)
- `lisp/modules/gptel-tools-agent.el` (8 kept / 22 discarded / 4 failed)
- `lisp/modules/gptel-benchmark-core.el` (20 kept / 31 discarded / 5 failed)

## Allium Behavioral Coherence

*4 behavioral issues (severity 0.00). EXTRACTED from Allium v3 pipeline.*



## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.




































































































## Allium Behavioral Spec (auto-generated, v3)

*3 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
## Distilled Research Strategy

**Framework:** `template-default` across **1986 experiments** targeting **~140 files** (lisp/modules/*, staging-*).

### Core Hypotheses (Kept)

The research tested improvements across five quality axes:

| Axis | Focus | Pattern |
|------|-------|---------|
| **φ Vitality** | Error resilience, adaptability | `nil` guards, validation before `plist-get`/`car` |
| **fractal Clarity** | Explicit assumptions, testable definitions | `proper-list-p` guards, named constants |
| **Performance (B)** | Algorithmic efficiency | Caching, O(n²)→O(n), pre-compiled regex |
| **Safety** | Defensive input handling | Type guards (`integerp`, `stringp`, `functionp`) |
| **Truth (∃)** | Correct behavior | Bug fixes in off-by-one, data structure misuse |

### High-Value Patterns Applied

1. **Nil/input validation** — Adding `(when (my/gptel--positive-integer-p X) ...)` guards before plist/hash operations
2. **proper-list-p over listp** — Dotted pairs (`(a . b)`) pass `listp` but fail `plist-get`/`cddr`
3. **Format-agnostic field access** — Replacing `plist-get` with helpers that handle both plist and alist (JSON round-trip)
4. **Extract duplicated logic** — 3+ identical code blocks → 1 named helper
5. **Cache computation** — Regex patterns, context windows, model metadata
6. **Fix plist-put/discarded-return** — `plist-put` returns new plist; must `setq`/`setf` back

### Discarded Hypotheses

- Adding explicit `proper-list-p` validation in `nucleus-tools-validate.el`
- String-literal filtering in `call-symbols-in-line` for false-positive detection
- FSM ID format validation (decimal vs scientific notation)
- `cl-lib` require and nil guards in ontology parsing
- Missing `:name` validation in tool spec argument processing
```

### Check Issues

## Verification Report

### Claims Check

| Claim | Status | Evidence |
|-------|--------|----------|
| **~140 files** targeted | ❌ Inaccurate | Found **110 .el files** in `lisp/*` |
| **1986 experiments** | ✅ Verified | Confirmed in `DIRECTIVE.md` header + `model-comparison.md` |
| **385 kept** | ✅ Verified | `total-kept: 385` in DIRECTIVE.md |
| **`template-default` framework** | ⚠️ Partial | Found in `analysis.json` but not in skills |
| **`proper-list-p` in nucleus-tools-validate.el** | ❌ Inverted | File **has** `proper-list-p` guards (contrary to "discarded" claim) |

### Verified Patterns (Evidence Found)

| Pattern | Status |
|----------|--------|
| `my/gptel--positive-integer-p` nil guards | ✅ Found in `gptel-ext-context-cache.el` |
| `proper-list-p` guards | ✅ Found in 4+ files |
| Cache definitions | ✅ 8+ `*cache*` vars found |
| `plist-put` without setq/setf | ⚠️ Found - potential bug |
| Type guards (`integerp`, `stringp`) | ✅ Present |

### Discrepancies Found

1. **File count**: Claims ~140 files, actual is **110 .el files** (26% inflation)
2. **nucleus-tools-validate.el**: Listed as "discarded hypothesis" but file **contains** `proper-list-p` validation - the hypothesis was **applied**
3. **Experiment count accuracy**: 1986 is a **metric** (total-experiments field), not necessarily distinct experiment runs (there's debate in the data if this is cumulative or unique)

### Summary

The core research strategy is **substantially accurate** with 1986 experiments and 385 kept

... (truncated)
