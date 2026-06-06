---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 0.6/10
allium-issues: 0
allium-severity: 0.00
allium-status: coherent
---

# Research Strategy: template-default

*Consolidated from 181 experiments (6% keep rate).*

**Performance:** 10 kept / 1 discarded / 21 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-tools-agent-prompt-build.el` (3 kept / 2 failed)
- `lisp/modules/gptel-auto-workflow-projects.el` (4 kept / 1 failed)
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

- `lisp/modules/gptel-auto-workflow-projects.el` (4 kept / 1 failed)
- `lisp/modules/gptel-auto-workflow-strategic.el` (4 failed)
- `lisp/modules/gptel-benchmark-subagent.el` (2 kept / 3 failed)
- `lisp/modules/gptel-tools-agent-error.el` (1 failed)
- `lisp/modules/gptel-tools-agent-prompt-build.el` (3 kept / 2 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.










## Allium Behavioral Spec (auto-generated, v3)

*3 check issues (severity 0.05). EXTRACTED from distill→check pipeline.*

```allium
## Distillation

**Meta-pattern:** All 7 kept hypotheses converge on two quality metrics—**φ Vitality** (adaptive, progressive, responsive to discovery) and **fractal Clarity** (explicit assumptions, minimal indirection). The 190 experiments collectively argue that this codebase's near-term gains lie in *defensive correctness* and *semantic transparency*, not in new features.

### Thematic clusters

| Cluster | Hypotheses | Common thread |
|---|---|---|
| **Idempotency / lifecycle** | H1 (advice idempotency + symmetric disable) | Symmetric enable/disable; no-op on repeat |
| **Cache semantics** | H3 (`eq` → `equal`, reorder validation) | Content-based invalidation; cheap checks first |
| **Nil/empty guards** | H2 (directory existence), H4 (FSM buffer lookup), H5 (empty projects + `ignore-errors`) | Validate preconditions explicitly, fail soft |
| **Complexity reduction** | H6 (`format-mode-line` → `mode-name`; `if` → `when`) | Prefer direct primitives; drop wrappers that obscure intent |
| **Latent-bug fix** | H7 (`not-applicable` filter before sort) | Pre-sort filtering prevents comparator from receiving incomparable types |

### Actionable shape (deduplicated)

1. **Lifecycle symmetry** — every advice-adding helper gets a mirror `*-remove` and a guard against double-activation.
2. **Precondition explicitness** — three sites currently *assume* (buffer alive, project list non-empty, directory present); each gets a named, local guard.
3. **One semantic fix** — `eq` → `equal` in project-list cache key; reorder so the cache hit short-circuits the expensive `ensure-buffer-tables` call.
4. **One crash fix** — filter incomparable symbols (`not-applicable`) out of the scores alist *before* `sort`.
5. **Two simplifications** — drop `format-mode-line` in favor of `mode-name`; replace `if` with `when` where no else-branch exists.

### What is *not* in scope

The discarded-hypothesis space is empty by signal (only "No hypothesis stated" entries), meaning **none of the 190 experiments rejected a tested hypothesis**. This is unusual and worth flagging: either the experiment harness is biased toward confirmation, or the filter upstream was already strict enough that only plausible candidates reached the experiment stage. Worth verifying before treating the kept set as exhaustive.

### Recommendation

Implement H3, H7 first (they fix *latent* correctness issues, not style). Then H1, H2, H4, H5 as a coherent defensive-validity pass. H6 is a cleanup that can ride along with any of the above.
```

### Check Issues

# Review of Distillation

Overall this is a tight, well-structured summary. A few things to tighten, and a couple of substantive issues worth addressing.

## What's working

- **Deduplication is defensible.** Collapsing H2/H4/H5 into "Precondition explicitness" is the right call — the three sites share the same *shape* of bug (implicit assumption → named guard), and treating them separately would inflate the action list.
- **Prioritization is justified.** H3 and H7 as latent-bug fixes first, then the defensive-validity pass, then H6 as ride-along cleanup. The reasoning ("latent correctness, not style") is the right criterion for sequencing.
- **The "not in scope" caveat is the most valuable sentence in the piece.** The empty discarded-hypothesis space is genuinely unusual and you're right to flag it as a signal about the experiment harness rather than about the codebase.

## Issues to address

### 1. The "empty by signal" phrase is unclear

> The discarded-hypothesis space is empty **by signal**

"By signal" doesn't parse cleanly. I read this as "based on the signal/evidence available" but it could also mean "by a wide margin" or "by default." Either tighten to something like *"the discard record shows zero rejected hypotheses"* or *"no discarded-hypothesis entries appear in the record"* — both are more concrete.

### 2. H1 conflates two distinct properties

The cluster cell says: *"Symmetric enable/disable; no-op on repeat"*

These are related but not the same:
- **Symmetric** = eve

... (truncated)
