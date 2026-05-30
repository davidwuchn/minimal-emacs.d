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

*0 check issues (severity 0.05). EXTRACTED from distill→check pipeline.*

```allium
**Distillation: Research Strategy (template-default) — 201 Experiments**

**Scope:** ~25 Elisp modules across `gptel-auto-workflow-*`, `gptel-tools-agent-*`, `gptel-benchmark-*`, `gptel-ext-*`, `nucleus-*`, `gptel-tools-memory`, and `gptel-agent-loop`.

---

### Kept Hypotheses (Defensive Correctness)

**Input Validation & Nil-Safety** — The dominant theme. Added guards to prevent runtime crashes from malformed agent output:
- `gptel-auto-experiment--validate-candidate-safely`, `gptel-auto-workflow-research-status-all`, `gptel-workflow--score-tools`: nil / non-string / empty-string checks.
- `gptel-benchmark--to-json-format`, `gptel-benchmark-summarize-results`: `(cl-every #'consp data)` and `proper-list-p` validation before destructuring.
- `gptel-benchmark-prescribe`, `gptel-auto-workflow--finalize-review-fix-result`: nil guards before string/pattern operations.
- `gptel-tools-memory--resolve-path`, `my/gptel-permit-tool`: slug and hash-table input validation.

**Data-Structure & Logic Bug Fixes** — Corrected concrete mismatches causing silent failures or inverted semantics:
- Fixed keyword-to-symbol alist conversion in `gptel-benchmark--to-json-format` (dotted pairs with keyword keys broke JSON serialization).
- Fixed `gptel-benchmark-diagnose-elements` using `plist-get` on alist data, causing scores to always default to 0.5; changed to `alist-get`.
- **Swapped inverted arguments** in `gptel-benchmark-baseline-file-compare`: caller passed `current` as version-a and `baseline` as version-b, inverting improvement/regression signals.
- Fixed stale-copy bug in `gptel-auto-workflow--link-shared-runtime-path` (regular files treated as valid symlinks).

**API Robustness & Error Signaling**
- Replaced non-built-in `hash-table-keys` usage (runtime errors in `my/gptel-show-permits` / `my/gptel-health-check`).
- Changed `gptel-tools-memory--read` / `--write` to signal errors instead of returning silent error strings.
- Extracted duplicated zero-result structure in `gptel-benchmark-summarize-results` into explicit helper `gptel-benchmark--empty-summary`.

---

### Discarded Hypotheses (Optimization & Structural)

**Performance / Memoization** — Deemed speculative or low-impact:
- Caching layers for `nucleus--project-root`, prompt/agent directory resolution, and `gptel-auto-workflow--safe-backend-name`.
- Micro-optimizations: removing redundant `cl-every` passes, temp-buffer elimination in `gptel-tools-memory--read`, `condition-case` restructuring.

**Test Infrastructure & File Structure**
- Moving misplaced `(provide 'gptel-benchmark-tests)` and 14 test definitions from after-provide to before-provide.
- Adding `unwind-protect` cleanup and fixing test state pollution in benchmark tests.
- Fixing race condition in `nucleus-sync-tool-profile` idle timer (`current-buffer` capture).

**Style & Scope Expansion**
- Misleading indentation fixes; `ignore-errors` vs `condition-case` preference.
- File-size validation for memory read; completing CRUD lifecycle + content-based search.

---

### Pattern

The strategy **accepted concrete, low-risk validation guards and correctness fixes** (Vitality and Clarity axes: nil-safety, type checking, argument-order bugs, proper error signaling) while **rejecting speculative performance optimizations, structural test reorganizations, and stylistic refactors** that did not address immediate runtime failure modes.
```

### Check Issues

This is a sharp, well-structured distillation. The boundary between **concrete runtime correctness** (kept) and **speculative/structural work** (discarded) is clear, and the Pattern summary accurately captures the decision logic.

A few critical checks and suggestions:

### 1. Likely Miscategorization: Race Condition
**`nucleus-sync-tool-profile` idle timer (`current-buffer` capture)** should probably move from **Discarded** to **Kept**.

Capturing `current-buffer` in a closure passed to an idle timer is a classic deferred-time bug: by the time the timer fires, the buffer may be killed, buried, or switched, causing the operation to run in the wrong context (or signal an error in a background timer). This is a **runtime correctness / nil-safety issue**, not speculative optimization or test infrastructure. Unless you have confirmed the timer is always cancelled synchronously before the buffer can change, this is defensive and low-risk.

### 2. Test Infrastructure: Correctness vs. Structure
The misplaced `(provide 'gptel-benchmark-tests)` and test state pollution sit on the boundary.
- If benchmark tests are run in CI or before releases, state pollution creates **non-deterministic failures** (correctness).
- If they are purely manual/debugging tools, discarding them as "structural" is justified.

**Check:** Are the benchmark tests part of the critical validation path? If yes, the `unwind-protect` cleanup and `provide` relocation are defensive correctness fixes and should be kep

... (truncated)
