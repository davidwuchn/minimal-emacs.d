---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 1.0/10
allium-issues: 0
allium-severity: 0.00
allium-status: coherent
---

# Research Strategy: template-default

*Consolidated from 201 experiments (10% keep rate).*

**Performance:** 20 kept / 48 discarded / 12 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-tools-agent-prompt-build.el` (1 kept / 3 discarded)
- `lisp/modules/gptel-auto-workflow-projects.el` (1 kept / 3 discarded)
- `lisp/modules/gptel-tools-agent-runtime.el` (1 kept / 1 discarded / 2 failed)
- `lisp/modules/gptel-benchmark-core.el` (5 kept / 7 discarded / 2 failed)
- `lisp/modules/gptel-ext-tool-permits.el` (3 kept / 2 discarded)
- `lisp/modules/gptel-benchmark-comparator.el` (1 kept / 1 discarded)
- `lisp/modules/gptel-tools-memory.el` (4 kept / 10 discarded)
- `lisp/modules/gptel-workflow-benchmark.el` (1 kept / 2 discarded / 5 failed)
- `lisp/modules/gptel-benchmark-principles.el` (2 kept / 1 discarded)
- `lisp/modules/gptel-tools-agent-staging-baseline.el` (1 kept / 3 discarded)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-auto-workflow--knowledge-cache-get, gptel-auto-workflow--knowledge-cache-set, gptel-auto-workflow--knowledge-cache-invalidate, gptel-auto-workflow--knowledge-cache-stats, gptel-auto-workflow--load-token-efficiency-data, gptel-auto-workflow--adapt-prompt-compression, gptel-auto-experiment--prompt-structure-score, gptel-auto-experiment--kibcm-axis, gptel-auto-experiment--forge-fixed-point, gptel-auto-experiment--compile-score, gptel-auto-experiment--decompile-score, gptel-auto-experiment--nucleus-compiler-prompt, gptel-auto-experiment--forge-lambda-fixed-point, gptel-auto-experiment--edn-richness-score, gptel-auto-experiment--count-edn-elements, gptel-auto-experiment--use-lambda-prompts-p, gptel-auto-experiment--lambda-compress-prompt, gptel-auto-experiment--resolve-prompt, gptel-auto-experiment--allium-compiler-prompt, gptel-auto-experiment--allium-distill
defvars: gptel-auto-workflow--skills), gptel-auto-experiment-large-target-byte-threshold), gptel-auto-workflow--last-prompt-sections), gptel-auto-workflow--current-research-context), gptel-auto-experiment-time-budget), gptel-auto-workflow-use-staging), gptel-auto-workflow--running), gptel-auto-workflow--stats), gptel-auto-experiment-validation-retry-active-grace), gptel-auto-workflow--legacy-validation-retry-active-grace), gptel-auto-workflow--current-validation-retry-active-grace), my/gptel-subagent-stream), gptel-auto-workflow--knowledge-cache, gptel-auto-workflow--knowledge-cache-max-age, gptel-auto-workflow--topic-knowledge-max-chars, gptel-auto-experiment--lambda-verified-backends, gptel-auto-experiment--allium-research-cache, gptel-auto-workflow--ab-test-sections, gptel-auto-workflow--ab-test-omit-rate, gptel-auto-workflow--ab-test-min-samples
requires: cl-lib, seq, subr-x, gptel-auto-workflow-strategic
provides: gptel-tools-agent-prompt-build
declares: gptel-agent-read-file, gptel-auto-workflow--valid-strategy-name-p, gptel-auto-workflow-load-research-findings, gptel-benchmark--detect-task-type, my/gptel-get-model-metadata, gptel-auto-workflow--current-run-id, gptel-auto-workflow--ensure-results-file, gptel-auto-workflow--make-idempotent-callback, gptel-auto-workflow--non-empty-string-p, gptel-auto-workflow--plist-get, gptel-auto-workflow--results-file-path, gptel-auto-workflow--worktree-base-root, gptel-auto-experiment--eight-keys-scores, gptel-auto-workflow--project-root, gptel-auto-workflow--persist-status, my/gptel--sanitize-for-logging, gptel-auto-workflow--extract-mutation-templates, gptel-auto-workflow--format-weakest-keys, gptel-auto-workflow-skill-suggest-hypothesis, gptel-auto-experiment--inspection-thrash-result-p
errors: Error, error, error, error, error, Error, signal, signal, error, error
handlers: nil, nil, err, err, err, err, err, err, nil
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-auto-workflow-strategic.el` (1 discarded / 1 failed)
- `lisp/modules/gptel-auto-workflow-evolution.el` (1 failed)
- `lisp/modules/gptel-tools-agent-runtime.el` (1 kept / 1 discarded / 2 failed)
- `lisp/modules/gptel-benchmark-core.el` (5 kept / 7 discarded / 2 failed)
- `lisp/modules/gptel-tools-agent-subagent.el` (1 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.




























<<<<<<< Updated upstream
## Allium Behavioral Spec (auto-generated, v3)

*0 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
**Distillation of 201 template-default experiments across ~30 Lisp modules**

### Bottom Line
The experiments surfaced a **robustness crisis, not a performance crisis**. The majority of accepted changes are defensive validation guards and correctness fixes in `gptel-auto-workflow-*`, `gptel-benchmark-*`, `gptel-tools-memory`, and `nucleus-*`. Performance-oriented hypotheses (memoization, caching, buffer optimization) were overwhelmingly discarded as unnecessary or premature.

---

### Accepted Themes (Kept Hypotheses)

**1. Input validation / nil-safety (≈60% of kept value)**
- **Pattern**: Add explicit guards for `nil`, non-string, empty-string, and improper-list inputs before processing.
- **Hotspots**: 
  - `gptel-auto-experiment--validate-candidate-safely`, `gptel-auto-workflow-research-status-all`, `gptel-workflow--score-tools`
  - `gptel-benchmark-summarize-results`, `gptel-benchmark-prescribe`, `gptel-benchmark--to-json-format`
  - `my/gptel-permit-tool`, `gptel-tools-memory--resolve-path`, `gptel-tools-memory--collect-dir`
- **Impact**: Prevents runtime crashes from malformed agent output or incomplete project data. Maps directly to **φ Vitality** (error resilience) and **fractal Clarity** (testable assumptions).

**2. Type/accessor mismatch bugs**
- `gptel-benchmark-diagnose-elements`: Used `plist-get` on alist data → switched to `alist-get` (scores were defaulting to 0.5).
- `gptel-benchmark--to-json-format`: Dotted-pair alists like `((:score . 0.8))` preserved keyword keys instead of converting to symbols, breaking JSON serialization.
- `hash-table-keys`: Not built-in in Emacs Lisp; usage in permit/health modules would cause runtime errors.
- `condition-case` handler: `(ignore)` is not a valid error condition in `gptel-auto-workflow--safe-truename`; replaced with `(error nil)` to make the "safe" wrapper actually safe.

**3. Logic/argument-order bugs**
- **`gptel-benchmark-baseline-file-compare`**: Caller passed `(current baseline)` but `compare-summaries` treats arg1 as baseline and arg2 as candidate, inverting improvement/regression signals. Swapped order.
- **`gptel-auto-workflow--link-shared-runtime-path`**: Regular files at target were treated as valid without creating symlinks, leaving stale copies.
- **`gptel-auto-workflow--finalize-review-fix-result`**: `string-match-p` could receive `nil` response.

**4. Structural & API consistency**
- **File structure**: Moved 14 test definitions and `(provide 'gptel-benchmark-tests)` to end-of-file (120+ lines had been stranded after the `provide`, breaking batch loading).
- **Memory module API**: `gptel-tools-memory--read` and `--write` now signal errors instead of returning error strings, preventing silent failures and making the API consistent.
- **Clarity refactors**: Extracted duplicated zero-result structure into `gptel-benchmark--empty-summary`; added keyword-plist helper to simplify nested score-extraction logic.

---

### Discarded Themes & Why

**1. Premature optimization / speculative caching**
- Memoization for `nucleus--project-root`, `nucleus--resolve-*-dir`, and `gptel-auto-workflow--safe-backend-name`.
- Rationale: Added state/complexity for marginal gain; the "hot paths" weren’t actually hot enough to justify cache invalidation logic.

**2. Micro-optimizations that broke safety or were unnecessary**
- Removing "redundant" `(cl-every #'consp data)` in `gptel-benchmark--to-json-format` to eliminate a "double-pass" — discarded because the check was load-bearing for safety.
- Optimizing `gptel-tools-memory--read` by removing `with-temp-buffer` — discarded (likely due to correctness or minimal gain).
- `gptel-ext-tool-permits.el` was already fully optimized from prior experiments (139 lines, down from 200); further changes had no headroom.

**3. Misleading simplifications**
- Removing `(consp val)(keywordp (car val))` checks that were already encoded in `inner-ht` — found to still be needed for guard logic.

---

### Meta-Observations

| Axis | Finding |
|------|---------|
| **Vitality (Error R
-- ... truncated ...
=======












## Allium Behavioral Spec (auto-generated, v3)

*3 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
**Distilled Research Strategy**

- **Template:** template-default
- **Experiments:** 8 total
- **Targets:** 6
  - 2 staging targets (review, merge, verification)
  - 4 Elisp module targets (strategic, projects, research-integration workflows)
- **Hypotheses:** None specified (kept or discarded)
>>>>>>> Stashed changes
```

### Check Issues

<<<<<<< Updated upstream
**Verdict: Technically sound and well-framed.** The distillation is sharp, internally consistent, and the “robustness crisis, not performance crisis” conclusion is strongly supported by the evidence you presented. A few minor technical notes and one likely inaccuracy to address before this is finalized:

---

### ✅ Confirmed / Strong

**1. The `(ignore)` → `(error nil)` fix is correct.**
In `condition-case`, a handler has the shape `(CONDITIONS . BODY)`. Writing `(ignore)` installs a handler for the *specific* signal symbol `ignore`, not a catch-all. To swallow any error and return `nil`, `(error nil)` is the right replacement. (Pedantic aside: you *could* define an error symbol named `ignore`, but it would never catch a standard `error` signal.)

**2. `plist-get` on alists and dotted-pair JSON keys are classic Elisp boundary bugs.**
Both fixes are exactly right. `plist-get` expects a property list (`:key val :key2 val2...`), not an alist. And JSON serialization paths in Emacs are notoriously sensitive to whether keys are keywords, symbols, or strings depending on `json-object-type` / `json-encoding-key-fn`.

**3. `string-match-p` on `nil` is a guaranteed `wrong-type-argument` error.**
Guard is necessary.

**4. Argument-order inversion in `gptel-benchmark-baseline-file-compare`.**
This is a high-severity silent bug—exactly the kind of thing that makes baseline/candidate comparisons useless. Good catch.

**5. `provide` stranded before EOF.**
A genuine structural/load-order bug. M

... (truncated)
=======
# Quick Review: Distilled Research Strategy

## Structure Analysis

| Element | Status | Notes |
|---------|--------|-------|
| Template | ✓ | Standard choice |
| Experiment count | ✓ | 8 experiments is reasonable |
| Target breakdown | ⚠️ | 6 targets with 2 staging + 4 modules |
| Hypotheses | ❓ | "None specified" — intentional? |

## Observations

**Potential Gaps:**
- No hypotheses defined — will experiments test specific claims?
- Unclear how 8 experiments distribute across 6 targets
- No priority or sequencing specified

**Questions to Consider:**
1. Are the 2 staging targets prerequisites for module targets?
2. What's the expected output of each Elisp module target?
3. Is "no hypotheses" by design, or an oversight?

## Need More Detail?

If you'd like a deeper review, share:
- Experiment descriptions
- Success criteria
- Timeline/deadlines

This helps validate the strategy is well-scoped.
>>>>>>> Stashed changes
