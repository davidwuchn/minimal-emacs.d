---
title: Optimization Skill: context
phi: 0.50
skill-type: optimization-target
target: lisp/modules/gptel-ext-context.el
created: 2026-03-23
runs: 0
mutation-skills:
  - mementum/knowledge/mutations/caching.md
  - mementum/knowledge/mutations/lazy-init.md
  - mementum/knowledge/mutations/simplification.md
---

# Optimization Skill: context

Target: `lisp/modules/gptel-ext-context.el`

## Overview

Context management for gptel conversations:
- Auto-compact when context exceeds threshold
- Auto-delegate large requests
- Token tracking and caching

## Key Functions

| Function | Purpose | Optimization Opportunity |
|----------|---------|--------------------------|
| `my/gptel--current-tokens` | Count tokens | Cache result per buffer |
| `my/gptel--effective-threshold` | Get threshold | Cache by backend type |
| `my/gptel-auto-compact-maybe` | Trigger compact | Defer until needed |

## Current Baseline

| Metric | Value |
|--------|-------|
| Eight Keys | (pending first run) |
| Code Quality | (pending) |
| Weakest Key | (pending) |

## Mutation Candidates

### Caching

```elisp
;; Cache token count (changes on edit)
(defvar-local my/gptel--token-cache nil)
(defvar-local my/gptel--token-cache-tick 0)

(defun my/gptel--current-tokens ()
  (let ((tick (buffer-modified-tick)))
    (if (and my/gptel--token-cache
             (= tick my/gptel--token-cache-tick))
        my/gptel--token-cache
      (setq my/gptel--token-cache-tick tick
            my/gptel--token-cache (gptel--token-count)))))
```

### Lazy Init

```elisp
;; Defer cache initialization
(defvar my/gptel--context-cache nil)

(defun my/gptel--get-context-cache ()
  (or my/gptel--context-cache
      (setq my/gptel--context-cache (make-hash-table))))
```

## Next Hypothesis

Based on module structure:

1. **Caching**: "Cache token count per buffer to reduce redundant counting"
2. **Lazy-init**: "Lazy initialize context cache to defer memory cost"
3. **Simplification**: "Extract threshold logic into single function"

## Nightly History

| Date | Experiments | Kept | Score Before | Score After | Delta |
|------|-------------|------|--------------|-------------|-------|
| (pending) | - | - | - | - | - |

## Signal Phrases to Include

For this module, focus on:

| Key | Signal | Where |
|-----|--------|-------|
| λ Efficiency | "caching", "optimizes" | Commit message |
| Clarity | "explicit assumptions", "testable" | Docstrings |

## Statistics

| Metric | Value |
|--------|-------|
| Total experiments | 0 |
| Kept | 0 |