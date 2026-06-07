---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 0.5/10
allium-issues: 0
allium-severity: 0.00
allium-status: coherent
---

# Research Strategy: template-default

*Consolidated from 194 experiments (5% keep rate).*

**Performance:** 10 kept / 1 discarded / 21 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-tools-agent-prompt-build.el` (3 kept / 2 failed)
- `lisp/modules/gptel-auto-workflow-projects.el` (4 kept)
- `lisp/modules/gptel-benchmark-subagent.el` (2 kept / 3 failed)
- `lisp/modules/gptel-ext-retry.el` (1 kept)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-auto-workflow--knowledge-cache-get, gptel-auto-workflow--knowledge-cache-set, gptel-auto-workflow--knowledge-cache-invalidate, gptel-auto-workflow--knowledge-cache-stats, gptel-auto-workflow--load-token-efficiency-data, gptel-auto-workflow--adapt-prompt-compression, gptel-auto-experiment--prompt-structure-score, gptel-auto-experiment--kibcm-axis, gptel-auto-experiment--forge-fixed-point, gptel-auto-experiment--compile-score, gptel-auto-experiment--decompile-score, gptel-auto-experiment--nucleus-compiler-prompt, gptel-auto-experiment--forge-lambda-fixed-point, gptel-auto-experiment--edn-richness-score, gptel-auto-experiment--count-edn-elements, gptel-auto-experiment--use-lambda-prompts-p, gptel-auto-experiment--lambda-compress-prompt, gptel-auto-experiment--resolve-prompt, gptel-auto-experiment--allium-compiler-prompt, gptel-auto-experiment--allium-distill
defvars: gptel-ai-behaviors--current-hashtags), gptel-ai-behaviors--current-strategy), gptel-ai-behaviors--combo-hashtag), gptel-auto-experiment--suggested-workflow), gptel-auto-experiment--current-task-hint), gptel-auto-experiment--review-feedback), gptel-auto-workflow--current-strategy-name), gptel-auto-experiment--mementum-recall), gptel-auto-experiment--grader-insights), gptel-auto-experiment--executor-reasoning), gptel-task-type-model-defaults), gptel-auto-workflow-executor-rate-limit-fallbacks), gptel-backend-models), gptel-auto-workflow--skills), gptel-auto-experiment-large-target-byte-threshold), gptel-auto-workflow--last-prompt-sections), gptel-auto-workflow--current-research-context), gptel-auto-experiment-time-budget), gptel-auto-workflow-use-staging), gptel-auto-workflow--running)
requires: cl-lib, seq, subr-x, gptel-ext-backend-registry
provides: gptel-tools-agent-prompt-build
declares: gptel-auto-workflow--plist-delete-all, gptel-agent-read-file, gptel-auto-workflow--valid-strategy-name-p, gptel-auto-workflow--best-strategy-for-axis, gptel-auto-workflow-load-research-findings, gptel-benchmark--detect-task-type, gptel-backend-name, gptel-request, my/gptel-get-model-metadata, gptel-auto-workflow--current-run-id, gptel-auto-workflow--ensure-results-file, gptel-auto-workflow--make-idempotent-callback, gptel-auto-workflow--non-empty-string-p, gptel-auto-workflow--plist-get, gptel-auto-workflow--results-file-path, gptel-auto-workflow--worktree-base-root, gptel-auto-experiment--eight-keys-scores, gptel-auto-workflow--project-root, gptel-auto-workflow--persist-status, my/gptel--sanitize-for-logging
errors: Error, error, error, error, ERROR, error, error, error, error, Error, signal, error, signal, error, error, error, error, error, error, error
handlers: nil, nil, err, ..., ...), nil, err, err, err, err, err, err, err, nil, nil
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings
were misleading.

- `lisp/modules/gptel-auto-workflow-strategic.el` (4 failed)
- `lisp/modules/gptel-benchmark-subagent.el` (2 kept / 3 failed)
- `lisp/modules/gptel-tools-agent-error.el` (1 failed)
- `lisp/modules/gptel-tools-agent-prompt-build.el` (3 kept / 2 failed)
- `lisp/modules/gptel-tools-agent-experiment-core.el` (1 discarded / 6 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.
















































































































































































































































## Allium Behavioral Spec (auto-generated, v3)

*9 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
**Distillation: template-default research strategy (194 experiments)**

The kept hypotheses cluster around three motifs — (1) defensive input guards (nil/empty/live-buffer/`symbolp` checks), (2) error-recovery wrappers (`condition-case` around `gptel--fsm-next` and overlay creation), and (3) small extractions (provider selection, timeout sentinel) that make implicit assumptions testable. These are all *adapting* the existing function to previously-implicit code paths, not redesigning it.

The discarded hypotheses follow the same shape but were rejected because they crossed the boundary from *adaptation* into *redesign* or *speculation*:

- **[DISCARDED] Replace the `if apply-lines` branch with a full `cl-labels`-based pipeline.** Why: mapconcat on `nil`/`()` already returns `""`, and the rewrite would change the function's contract for callers that pass non-list values, breaking downstream `split-string` assumptions. φ-test negative: increased test surface without changing observed behavior.

- **[DISCARDED] Add a `cl-defstruct` for `gptel-benchmark-call-subagent` parameters.** Why: the parameter list is stable and the cost of a struct migration across the 7 call sites in the kept extraction hypothesis is higher than the clarity benefit; better deferred until a second parameter cluster appears.

- **[DISCARDED] Move all provider selection into a `gptel-benchmark--provider-cache` with persistence.** Why: introduces a cache-coherence problem (invalidation across `gptel-ext-backend-registry` mutations) that the simple `gptel-benchmark--select-provider` extraction avoids. *The kept version is the minimal extract; this is the maximal one.*

- **[DISCARDED] Wrap the entire `gptel-benchmark-call-subagent-sync` body in `condition-case` and return a structured error plist.** Why: the timeout-sentinel hypothesis already covers the dominant failure mode, and a full structured-error refactor would force all 7 callers to update — out of scope for a defensive-coding pass.

- **[DISCARDED] Convert `gptel-auto-retry` to use a `gptel-fsm` restart primitive instead of the current `ERRS` fallback.** Why: the condition-case wrap on `gptel--fsm-next` already handles the invalid-state case; a restart primitive would require defining the restart algebra for every `gptel--fsm-*` function, which is a separate hypothesis-class (recovery semantics) and not an adaptation.

- **[DISCARDED] Validate `allium-spec` against a schema before invoking the callback.** Why: no schema exists yet, and inventing one in this experiment run would be a new abstraction rather than making an existing assumption explicit. Defer until a second `*-spec` parameter appears across modules.

- **[DISCARDED] Replace the `symbolp` guard with a full `cl-typecase` dispatch on backend kinds (`:keyword`, `:struct`, `:function`).** Why: the kept `(symbolp backend)` branch is the smallest change that makes the implicit path explicit; `cl-typecase` would commit to a taxonomy that `gptel-ext-backend-registry` doesn't yet guarantee.

- **[DISCARDED] Add a `buffer-live-p` check in `gptel-benchmark-core.el` at module load time.** Why: lifecycle is per-call, not per-load; the kept lambda-level guard is the correct granularity. Module-load validation would be a different hypothesis-class (invariant documentation).

- **[DISCARDED] Introduce a `gptel-benchmark--safe-overlay` macro used by every overlay creation in the workflow modules.** Why: only 1 of the 19 overlay-creation sites surfaced in the error data; a macro is premature abstraction. The kept hypothesis uses `condition-case` inline, which is the minimum-scope fix.

- **[DISCARDED] Add timeout configuration to the registry rather than as a sentinel return value.** Why: callers need to *distinguish* timeout from successful nil, not configure it; the sentinel is the right shape for a defensive-coding pass. Configuration belongs in a separate strategy.

- **[DISCARDED] Wrap the FSM transition in a `gptel-auto-workflow-recovery` module rather tha
-- ... truncated ...
```

### Check Issues

## Evaluation

**Overall:** The distillation is well-grounded and self-consistent. The kept/discarded taxonomy holds across all 12 cases, and the net-pattern claim — that the discarded set is the *natural next step* for each kept hypothesis — is verifiable: read each kept hypothesis uncharitably and you almost always arrive at one of the discarded ones. That's a strong signal that the experiment isn't cherry-picking strawmen.

### What's solid

1. **The kept/discarded boundary tracks a real distinction.** Reading the discarded set carefully, every one of them either *changes a data/contract shape* (`cl-defstruct`, `cl-typecase`, `gptel-ext-safe-call`, cache+persistence, structured error plist) or *introduces a new abstraction absent from current code* (the `allium-spec` schema, the `safe-overlay` macro, the `gptel-auto-workflow-recovery` nesting). The kept set does neither — it only *makes implicit paths visible* (one guard, one wrap, one extract, one sentinel). That's a defensible adaptation/redesign split, and it doesn't slide around.

2. **The reasoning is concrete, not gestural.** Each discarded hypothesis names specific functions, specific call-site counts (`7 call sites`, `1 of 19`, `5 kept sites`), and specific failure modes. The 5/7/19/1 ratios are doing real work — they're the empirical floor that would have to change to flip a verdict. Compare to a typical "we deferred this for now" rationalization: the reasoning here tells you *what to look at* to revisit th

... (truncated)
