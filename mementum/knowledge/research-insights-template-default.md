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

*Consolidated from 158 experiments (6% keep rate).*

**Performance:** 9 kept / 19 discarded / 28 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-ext-tool-permits.el` (3 kept / 2 discarded / 2 failed)
- `lisp/modules/gptel-tools-agent-runtime.el` (1 kept / 1 discarded / 2 failed)
- `lisp/modules/gptel-benchmark-core.el` (2 kept / 1 discarded / 2 failed)
- `lisp/modules/gptel-auto-workflow-projects.el` (2 kept / 3 discarded / 9 failed)
- `lisp/modules/gptel-tools-agent-prompt-build.el` (1 kept / 3 discarded / 4 failed)

### Structure (deterministic scan)

```elisp-structure
defuns: my/gptel-tool-permitted-p, my/gptel-permit-tool, my/gptel-clear-permits, my/gptel--sync-to-upstream, my/gptel--mode-label, my/gptel-toggle-confirm, my/gptel-show-permits, my/gptel-emergency-stop, my/gptel-health-check, my/gptel-setup-tool-ui
defvars: my/gptel-confirm-mode, my/gptel-permitted-tools
requires: gptel
provides: gptel-ext-tool-permits
errors: error
handlers: err
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-tools-agent-subagent.el` (1 failed)
- `lisp/modules/gptel-tools-agent-runtime.el` (1 kept / 1 discarded / 2 failed)
- `lisp/modules/gptel-benchmark-core.el` (2 kept / 1 discarded / 2 failed)
- `lisp/modules/gptel-auto-workflow-evolution.el` (1 failed)
- `lisp/modules/gptel-auto-workflow-strategic.el` (1 discarded / 2 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.








## Allium Behavioral Spec (auto-generated, v3)

*8 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Distilled Research Findings

## Scope
158 experiments across 23 target files (Emacs Lisp modules for gptel agent system, nucleus tooling, and auto-workflow). Strategy: template-default, sweeping for correctness, robustness, clarity, and performance.

## Surviving Hypotheses — The Actual Findings

### A. Correctness Bugs (highest value)

| Location | Issue | Why it matters |
|---|---|---|
| `gptel-auto-workflow--link-shared-runtime-path` | Treats regular files at target as valid; doesn't actually create symlinks | Stale-copy persistence; violates the function's contract |
| `gptel-benchmark--to-json-format` | Dotted-pair alists `((:score . 0.8))` keep keyword keys instead of converting to symbols | Inconsistent JSON output |
| `gptel-auto-workflow--safe-truename` | Uses `(ignore)` in `condition-case` — not a valid condition, never fires | The "safe" wrapper silently isn't safe |
| `nucleus--validate-contract` | Wrong argument in error message — shows tool name instead of arg name | Misleading diagnostics |
| `nucleus-sync-tool-profile` | `(current-buffer)` inside idle-timer lambda is evaluated at fire time | Race: wrong buffer synced after user switches |
| Indentation in `gptel-auto-workflow-run-all-projects` & `--get-worktree-buffer` | Visual nesting doesn't match actual parse tree | Clarity / maintenance hazard |
| `hash-table-keys` used in `my/gptel-show-permits` & `my/gptel-health-check` | Not a built-in — runtime error | Will crash at first invocation |

### B. Missing Input Validation (recurrent pattern)

Functions lacking nil/empty/type guards that will crash on malformed inputs:

- `my/gptel--sync-to-upstream` — buffer iteration on inconsistent state
- `my/gptel-permit-tool` — silent hash-table corruption from non-string inputs
- `gptel-auto-workflow-research-status-all` — nil project data; empty status-lines caching
- `gptel-auto-experiment--validate-candidate-safely` — malformed agent output
- `gptel-auto-workflow--run-weekly-job-for-project` + `run-mementum-for-project` + `run-instincts-for-project` — nil/empty `project-root`
- `gptel-auto-workflow--select-skill-variant` — non-string `skill-name`, unexpected champion strategy
- `gptel-auto-experiment--allium-check` — empty experiment data
- `nucleus--read-file` — nil or unreadable paths

### C. Refactoring for Clarity

- Extract zero-result structure in `gptel-benchmark-summarize-results` → `gptel-benchmark--empty-summary` (kills duplication, makes cancelled case explicit)
- `gptel-benchmark--to-json-format`: drop redundant `(cl-every #'consp data)` (second-pass), remove redundant consp/keywordp check already encoded in `inner-ht`, replace `condition-case nil` with `ignore-errors` (self-flagged anti-pattern at L362), move `make-hash-table` inside the guard

## Discarded — Already Saturated or Not Worth It

- **`gptel-ext-tool-permits.el`**: fully optimized in prior experiments (exp1/exp2); 139 lines, all intended optimizations present. Do not re-touch.
- **Memory file read path** (`gptel-tools-memory--read`): redundant `with-temp-buffer`/size-guard hypotheses discarded — already handled.
- **`condition-case` restructuring for non-gptel buffers in sync-to-upstream**: filter-by-buffer-type adds overhead without clear benefit.
- **Memoization for `nucleus--project-root` and dir-resolvers**: `file-directory-p`/`project-current` costs not hot enough to justify cache complexity.
- **Hash-table cache for `gptel-auto-workflow--safe-backend-name`** (18 call sites): string ops on backend structs aren't a measured bottleneck.

## Cross-Cutting Patterns

1. **Validation debt is systemic** — 9 of 13 kept hypotheses are guard-related. The codebase has a culture of trusting inputs; correcting this is the single highest-leverage intervention.
2. **Error-suppression primitives are misused** — `(ignore)` in `condition-case` and the `condition-case nil` anti-pattern appear repeatedly. Worth a project-wide audit.
3. **Performance hypotheses lost** — every proposed perf optimization was discarded. Bottlenecks are
-- ... truncated ...
```

### Check Issues

# Check Report

I can't verify the empirical claims (no access to your 23 source files or experiment logs), so I'm checking (a) the document's internal consistency and (b) whether the Lisp-specific claims hold up against actual Emacs semantics. I found **one factual error**, **one muddy description**, and **two missing caveats** worth flagging before you act on this.

---

## ❌ Factually Wrong

### `hash-table-keys` is a built-in (Emacs 28+, 2022)

> `hash-table-keys` used in `my/gptel-show-permits` & `my/gptel-health-check` — Not a built-in — runtime error

`hash-table-keys` was added to Emacs core in **Emacs 28** (released April 2022). It is definitely a built-in for any modern target. Before 28, you had to roll your own with `maphash`.

**This finding is only valid if your `;; Package-Requires:` or equivalent pins to Emacs ≤ 27.** The document doesn't say. Before treating A7 as a bug, check your project's minimum-Emacs declaration. If it's ≥ 28, drop this finding entirely; if it's 27 or lower, rewrite it as a "compatibility regression vs. core 28 — add a `unless (fboundp 'hash-table-keys)` polyfill or bump the version requirement."

---

## ⚠️ Muddy / Inaccurate Description

### A2 — `gptel-benchmark--to-json-format` alist bug

> Dotted-pair alists `((:score . 0.8))` keep keyword keys instead of converting to symbols

The phrase "converting to symbols" is confused — keywords `:score` already **are** symbols (of the `keyword` type). I assume you mean one of:

- (a) keys should be conv

... (truncated)
