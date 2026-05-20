---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 1.9/10
allium-issues: 6
allium-severity: 0.05
allium-status: ok
---

# Research Strategy: template-default

*Consolidated from 1827 experiments (19% keep rate).*

**Performance:** 354 kept / 1039 discarded / 23 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-benchmark-principles.el` (1 kept / 1 discarded / 2 failed)
- `lisp/modules/gptel-benchmark-core.el` (20 kept / 48 discarded / 1 failed)
- `lisp/modules/gptel-auto-workflow-strategic.el` (11 kept / 37 discarded / 3 failed)
- `lisp/modules/gptel-tools-agent.el` (61 kept / 156 discarded / 1 failed)
- `lisp/modules/gptel-ext-tool-sanitize.el` (39 kept / 72 discarded / 5 failed)
- `lisp/modules/gptel-tools-memory.el` (2 kept / 3 discarded)
- `lisp/modules/gptel-sandbox.el` (29 kept / 75 discarded)
- `lisp/modules/gptel-ext-fsm-utils.el` (34 kept / 68 discarded)
- `lisp/modules/gptel-ext-context-cache.el` (30 kept / 92 discarded)
- `lisp/modules/gptel-tools-agent-git.el` (7 kept / 16 discarded / 1 failed)

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

- `lisp/modules/gptel-benchmark-principles.el` (1 kept / 1 discarded / 2 failed)
- `lisp/modules/gptel-auto-workflow-strategic.el` (11 kept / 37 discarded / 3 failed)
- `lisp/modules/gptel-tools-agent.el` (61 kept / 156 discarded / 1 failed)
- `lisp/modules/gptel-ext-tool-sanitize.el` (39 kept / 72 discarded / 5 failed)
- `lisp/modules/gptel-tools-agent-validation.el` (1 kept / 3 discarded / 1 failed)

## Allium Behavioral Coherence

*6 behavioral issues (severity 0.05). EXTRACTED from Allium v3 pipeline.*



## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.








## Allium Behavioral Spec (auto-generated, v3)

*4 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
## Research Strategy: Template-Default — Distilled

**1827 experiments across 60+ Elisp targets** focused on improving code quality metrics: **φ Vitality** (adaptive error recovery), **fractal Clarity** (explicit assumptions, testable definitions), and **Performance**.

### Core Hypotheses (Kept)

| Category | Hypothesis | Impact |
|----------|-----------|--------|
| **plist misuse** | Replacing `plistp`/`listp` with `proper-list-p` prevents silent failures on dotted pairs | Safety + Clarity |
| **nil guards** | Adding `proper-list-p` / `stringp` validation at entry points prevents runtime crashes | Vitality (error resilience) |
| **duplication** | Extracting repeated patterns into helpers (`gptel-tools-agent--ensure-module-dir`, `gptel-benchmark--get-field`) | Clarity + Maintainability |
| **performance** | Caching regex patterns, git state, context-window lookups reduces O(n) to O(1) | Vitality (performance axis) |
| **FSM bugs** | Fixing `prog1 t` return discarding recursive results; fixing global symbol properties → FSM-local state for doom-loop detection | Correctness |
| **format mismatch** | `plist-get` fails on alists (post-JSON round-trip); delegate to format-agnostic helpers | Correctness |

### Discarded Hypotheses

- Extracting `:eight-keys` nested plist into helper (accumulation bug fix)
- Extracting scores once per result in `gptel-benchmark-analyze-patterns`
- Various caching/optimization proposals that didn't survive verification

### Key Files Studied

- `gptel-ext-fsm-utils.el` — FSM traversal, cycle detection, registry validation
- `gptel-ext-tool-sanitize.el` — tool sanitization, nil guards
- `gptel-tools-agent.el` — workflow automation, error handling
- `gptel-sandbox.el` — tool execution, validation
- `gptel-benchmark-*.el` — benchmark infrastructure

### Recurring Patterns Fixed

1. **`proper-list-p` vs `listp`** — `listp` returns t for dotted pairs; `proper-list-p` catches malformed data
2. **Missing `nil` guards** — Entry points lacked validation for nil/empty inputs
3. **`plist-put` return values discarded** — Changes never persisted (`setf (gptel-fsm-info fsm) ...` missing)
4. **`plist-get` on alists** — After JSON serialization, plists become alists; need `gptel-benchmark--get-field` helper
```

### Check Issues

# Review: Research Strategy Summary

## Overall Assessment

**Well-structured** documentation of an Elisp code quality initiative. The template effectively separates kept vs. discarded hypotheses. Some areas need clarification or tightening.

---

## Issues to Address

### 1. Specificity Inconsistency

| What It Says | Concern |
|--------------|---------|
| "1827 experiments" | Precise number needs source/verification |
| "60+ Elisp targets" | Rounded ("60+") contradicts exact "1827" |

**Recommendation:** Either both exact or both approximate.

### 2. Core Hypotheses Table — Vague Entries

```
"Extracting repeated patterns into helpers" — Which helpers?
"Reducing O(n) to O(1)" — Which specific cache operations?
```

These need concrete examples or references to specific functions.

### 3. Discarded Hypotheses Section Is Thin

Only 3 items mentioned. If 1827 experiments were run, expect more discards.

**Missing:**
- What criteria caused rejection?
- Any patterns in what didn't survive?

### 4. Symbols in "φ Vitality" / "fractal Clarity"

- `φ` (phi) — is this a named metric or decorative?
- "fractal Clarity" — what does fractal mean in this context?

**Recommendation:** Use plain terms unless these are defined elsewhere.

---

## What's Solid

✅ **plist/alist distinction** — Accurate and important Elisp pitfall  
✅ **`prog1 t` bug** — Real Emacs gotcha  
✅ **File inventory** — Specific and traceable  
✅ **Recurring patterns** — Actionable bullet points  

---

## Suggested Improvements

1. Add methodology secti

... (truncated)
