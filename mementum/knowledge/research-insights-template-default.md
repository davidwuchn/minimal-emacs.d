---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 0.2/10
allium-issues: 3
allium-severity: 0.05
allium-status: ok
---

# Research Strategy: template-default

*Consolidated from 103 experiments (2% keep rate).*

**Performance:** 1 kept / 3 discarded / 21 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-auto-workflow-projects.el` (1 kept / 2 discarded / 9 failed)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-auto-workflow--knowledge-cache-get, gptel-auto-workflow--knowledge-cache-set, gptel-auto-workflow--knowledge-cache-invalidate, gptel-auto-workflow--knowledge-cache-stats, gptel-auto-workflow--load-token-efficiency-data, gptel-auto-workflow--adapt-prompt-compression, gptel-auto-experiment--prompt-structure-score, gptel-auto-experiment--kibcm-axis, gptel-auto-experiment--forge-fixed-point, gptel-auto-experiment--compile-score, gptel-auto-experiment--decompile-score, gptel-auto-experiment--nucleus-compiler-prompt, gptel-auto-experiment--forge-lambda-fixed-point, gptel-auto-experiment--edn-richness-score, gptel-auto-experiment--count-edn-elements, gptel-auto-experiment--use-lambda-prompts-p, gptel-auto-experiment--lambda-compress-prompt, gptel-auto-experiment--resolve-prompt, gptel-auto-experiment--allium-compiler-prompt, gptel-auto-experiment--allium-distill
defvars: gptel-auto-workflow--skills), gptel-auto-experiment-large-target-byte-threshold), gptel-auto-workflow--last-prompt-sections), gptel-auto-workflow--current-research-context), gptel-auto-experiment-time-budget), gptel-auto-workflow-use-staging), gptel-auto-workflow--running), gptel-auto-workflow--stats), gptel-auto-experiment-validation-retry-active-grace), gptel-auto-workflow--legacy-validation-retry-active-grace), gptel-auto-workflow--current-validation-retry-active-grace), my/gptel-subagent-stream), gptel-auto-workflow--knowledge-cache, gptel-auto-workflow--knowledge-cache-max-age, gptel-auto-workflow--topic-knowledge-max-chars, gptel-auto-experiment--lambda-verified-backends, gptel-auto-experiment--allium-research-cache, gptel-auto-workflow--ab-test-sections, gptel-auto-workflow--ab-test-omit-rate, gptel-auto-workflow--ab-test-min-samples
requires: cl-lib, seq, subr-x
provides: gptel-tools-agent-prompt-build
declares: gptel-agent-read-file, gptel-auto-workflow--valid-strategy-name-p, gptel-auto-workflow-load-research-findings, gptel-benchmark--detect-task-type, my/gptel-get-model-metadata, gptel-auto-workflow--current-run-id, gptel-auto-workflow--ensure-results-file, gptel-auto-workflow--make-idempotent-callback, gptel-auto-workflow--non-empty-string-p, gptel-auto-workflow--plist-get, gptel-auto-workflow--results-file-path, gptel-auto-workflow--worktree-base-root, gptel-auto-experiment--eight-keys-scores, gptel-auto-workflow--project-root, gptel-auto-workflow--persist-status, my/gptel--sanitize-for-logging, gptel-auto-workflow--extract-mutation-templates, gptel-auto-workflow--format-weakest-keys, gptel-auto-workflow-skill-suggest-hypothesis, gptel-auto-experiment--inspection-thrash-result-p
errors: Error, error, error, ERROR, error, error, error, Error, signal, error, signal, error, error, error, error, error, error, error
handlers: nil, nil, err, ..., ...), err, err, err, err, err, nil
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-tools-agent-prompt-build.el` (4 failed)
- `lisp/modules/gptel-tools-agent-error.el` (2 failed)
- `lisp/modules/gptel-benchmark-principles.el` (2 failed)
- `lisp/modules/gptel-auto-workflow-projects.el` (1 kept / 2 discarded / 9 failed)
- `lisp/modules/treesit-agent-tools-workspace.el` (1 failed)

## Allium Behavioral Coherence

*3 behavioral issues (severity 0.05). EXTRACTED from Allium v3 pipeline.*



## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.
























## Allium Behavioral Spec (auto-generated, v3)

*6 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
**Research Strategy: Template-Default Distillation**

---

**Context:** 65 experiments across targets including `staging-verification`, `staging-merge`, `staging-review`, and various Lisp modules.

---

**Kept Hypotheses:**

1. **Idempotency Guard + Symmetric Disable** — Add guard to prevent re-adding active advice; extract symmetric disable function.
   - Targets: φ Vitality (progressive improvement), fractal Clarity (explicit assumptions, testable)

2. **Message Fix + Directory Validation** — Fix misleading message; add directory existence validation.
   - Type: Bug fix

3. **Cache Comparison Fix** — `gptel-auto-workflow--normalized-projects` uses `eq` (identity) for project list comparison, causing unnecessary invalidation. Change to `equal` (content) and check cache before `ensure-buffer-tables`.
   - Targets: φ Vitality (adapts to usage patterns), fractal Clarity (cache invalidation is content-based, not identity-based)

4. **Buffer Lookup Extraction** — Extract into clear validation sequence with explicit nil guards.
   - Targets: Clarity (visible assumptions), Vitality (graceful FSM state handling)

5. **Error Recovery + Edge Cases** — Add `ignore-errors` around `file-attributes`; add early guard for empty project lists.
   - Targets: φ Vitality (adapts to edge cases), fractal Clarity (explicit project validity assumptions)

6. **Mode-Line Simplification** — Replace `format-mode-line` with direct `mode-name` access; use `when` instead of `if`; add nil-safety guard for buffer iteration.
   - Target: fractal Clarity (removes unnecessary complexity)

---

**Discarded Hypotheses:**

- `gptel-benchmark-eight-keys-weakest` crashes when sorting scores with `not-applicable` symbols (causes `<` comparison error). Filter `not-applicable` entries before sorting to prevent runtime error.
  - Targets: Clarity (explicit data filtering), Vitality (latent bug discovery)
```

### Check Issues

# Review: Research Strategy Template-Default Distillation

## Summary Assessment

**Verdict: Incomplete / Needs Clarification**

---

## Critical Questions

### 1. Experiment Lossage
65 experiments → 7 hypotheses is a **97% discard rate**. What happened to the other 58?

| Scenario | Implication |
|----------|-------------|
| Merged into these 7 | Need consolidation narrative |
| Invalid results | Need failure analysis |
| Redundant | Need deduplication rationale |
| Never ran | Strategy document is premature |

### 2. Hypothesis 7 (Discarded) — Actually Stronger Than Some Kept

```
- crash when sorting → runtime error
- filter before sort → surgical fix
- addresses latent bug → high value
```

This should **not** be discarded. The `not-applicable` filtering hypothesis is more concrete and actionable than several kept hypotheses (e.g., "symmetric disable function extraction").

### 3. φ Notation Inconsistency

```
Hypothesis 1: "φ Vitality"
Hypothesis 3: "φ Vitality"
Hypothesis 5: "φ Vitality"

Hypothesis 2: No φ prefix (just "Bug fix")
Hypothesis 4: No φ prefix
```

**What does φ denote?** If it marks priority, why skip hypotheses 2 and 4?

### 4. Missing Information

| Element | Status |
|---------|--------|
| Hypothesis prioritization | ❌ Absent |
| Expected effort/impact | ❌ Absent |
| Success criteria | ❌ Absent |
| Experiment-to-hypothesis mapping | ❌ Absent |
| Interaction dependencies | ❌ Absent |

---

## Hypothesis Quality Assessment

| # | Hypothesis | Strength | Issue |
|---|------------|----------|--

... (truncated)
