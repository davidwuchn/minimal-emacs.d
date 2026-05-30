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














## Allium Behavioral Spec (auto-generated, v3)

*0 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
**Distillation of 201-Experiment Research Strategy**

**Meta-pattern: Safety > Performance**
Kept hypotheses overwhelmingly favor input validation, nil-safety, and functional correctness over caching, memoization, or micro-optimizations. Discarded hypotheses were predominantly speculative performance gains (memoized project roots, backend-name caching, eliminated temp buffers) or stylistic refactors (indentation, redundant guard removal) that did not address demonstrated failure modes.

---

**Critical Functional Bugs (Kept)**

- **Non-existent function:** `hash-table-keys` is not built-in Emacs Lisp; it breaks `my/gptel-show-permits` and `my/gptel-health-check` at runtime.
- **Inverted comparison logic:** `gptel-benchmark-baseline-file-compare` had swapped arguments, reversing improvement/regression signals (it computed `score-b - score-a` but passed current as `version-a` and baseline as `version-b`).
- **Wrong accessor type:** `gptel-benchmark-diagnose-elements` used `plist-get` on alist data, causing all scores to default to 0.5.
- **Broken error handler:** `gptel-auto-workflow--safe-truename` used `(ignore)` as a `condition-case` label, which never catches errors; replaced with `(error nil)`.
- **Stale copy vs. symlink:** `gptel-auto-workflow--link-shared-runtime-path` treated existing regular files as valid without ensuring they are symlinks, violating runtime path expectations.
- **JSON serialization mismatch:** `gptel-benchmark--to-json-format` preserved keyword keys in dotted-pair alists (e.g., `((:score . 0.8))`) instead of converting them to symbol keys, causing inconsistent JSON output.

---

**Systematic Hardening (Kept)**

- **Input validation:** Added nil/non-string/empty guards to experiment validation, workflow status, permit tools, memory path resolution, and benchmark processing.
- **List safety:** Replaced `listp` with `proper-list-p` and added `cl-every #'consp` checks across benchmark scoring, summarization, and JSON conversion to prevent crashes on malformed lists.
- **API consistency:** `gptel-tools-memory--read/write` now signal errors instead of returning strings, eliminating silent failures.
- **Slug safety:** Added filesystem-safe slug validation to memory path resolution.
- **Clarity refactors:** Extracted duplicated zero-result summary logic in `gptel-benchmark-summarize-results` into a dedicated helper.
- **Test infrastructure:** Moved misplaced `(provide 'gptel-benchmark-tests)` to the end of the file, added missing `(require 'cl-lib)`, fixed log append vs. overwrite, and isolated global state in evolution tests.

---

**Rejected Directions**

- **Memoization / caching:** Caching for `nucleus--project-root`, prompt directories, and backend names was discarded—treated as premature optimization without a proven hot-path bottleneck.
- **Micro-optimizations:** Removing double-pass `cl-every`, restructuring `condition-case` scope, and eliminating temp buffers in memory read were rejected in favor of clarity and safety.
- **Stylistic-only refactors:** Misleading indentation fixes and speculative hash-table allocation moves were discarded as non-functional.

---

**Bottom Line**
The accepted changes form a coherent defensive pass: make every boundary (user input, agent output, git results, file reads, JSON deserialization) explicitly validate its assumptions, fix the small set of logic inversions and non-existent function calls that cause silent data corruption, and keep error signaling consistent. Performance optimizations were deferred until safety invariants are enforced.
```

### Check Issues

This is a tight, accurate distillation. The safety-first meta-pattern is well-justified, and the technical claims hold up under scrutiny. A few confirmations and minor nuances:

**Verified / Correct**
- **`hash-table-keys`**: Correctly identified as missing. It lives in `subr-x` (since Emacs 24.4) and is not autoloaded/preloaded. If the file didn’t explicitly require it, calling it signals `void-function`.
- **`(ignore)` in `condition-case`**: Excellent catch. Handlers match signal *symbols*, so `(ignore)` only catches a signal literally named `ignore`, which is not what standard errors emit. `(error nil)` is the correct universal catch-and-return-nil pattern.
- **`plist-get` on alists**: Classic silent data corruption. `plist-get` walks by `cddr` expecting flat `:key val` pairs; on an alist it either returns nil or misreads car/cdr structure.
- **Inverted benchmark logic**: The argument swap is a high-severity silent failure—exactly the kind of bug that makes defensive validation worth prioritizing over perf tweaks.
- **JSON keyword keys**: `json-encode` and friends generally prefer symbols or strings. Keyword keys in dotted pairs often serialize inconsistently or retain the colon, so normalizing to symbols upstream is the right fix.

**Nuance / Ensure Compatibility**
- **`proper-list-p`**: This was added to `subr-x` in Emacs 27.1. If `gptel` supports older Emacs, you may need a compatibility shim or an explicit `(require 'subr-x)`. The distillation notes you added `(re

... (truncated)
