---
title: Optimization Skill: code
phi: 0.50
skill-type: optimization-target
target: lisp/modules/gptel-tools-code.el
created: 2026-03-23
runs: 0
mutation-skills:
  - mementum/knowledge/mutations/caching.md
  - mementum/knowledge/mutations/lazy-init.md
  - mementum/knowledge/mutations/simplification.md
---

# Optimization Skill: code

Target: `lisp/modules/gptel-tools-code.el`

## Overview

Code navigation and analysis tools:
- Find usages (git-grep, LSP)
- Code replacement with truncation
- Diagnostics integration
- Treesit error detection

## Key Functions

| Function | Purpose | Optimization Opportunity |
|----------|---------|--------------------------|
| `my/gptel--find-usages` | Find symbol usages | Cache results with TTL |
| `my/gptel--usages-cache-*` | Cache management | Already has caching |
| `my/gptel--detect-treesit-language` | Detect language | Cache by file extension |

## Current Baseline

| Metric | Value |
|--------|-------|
| Eight Keys | (pending first run) |
| Code Quality | (pending) |
| Weakest Key | (pending) |

## Mutation Candidates

### Caching

```elisp
;; Cache language detection by file extension
(defvar my/gptel--language-cache (make-hash-table :test 'equal))

(defun my/gptel--detect-treesit-language (file-path)
  (let* ((ext (file-name-extension file-path))
         (cached (gethash ext my/gptel--language-cache)))
    (or cached
        (puthash ext 
                 (my/gptel--detect-treesit-language-impl file-path)
                 my/gptel--language-cache))))
```

### Simplification

```elisp
;; Extract common pattern: fallback chain
(defmacro my/gptel--with-fallback-chain (primary fallback &rest body)
  "Try PRIMARY, then FALLBACK, then BODY."
  `(or (,primary) (,fallback) ,@body))
```

## Next Hypothesis

Based on module structure:

1. **Caching**: "Cache language detection by file extension to reduce redundant detection"
2. **Simplification**: "Extract fallback chain pattern into macro"
3. **Lazy-init**: "Lazy initialize usages cache until first lookup"

## Nightly History

| Date | Experiments | Kept | Score Before | Score After | Delta |
|------|-------------|------|--------------|-------------|-------|
| (pending) | - | - | - | - | - |

## Signal Phrases to Include

For this module, focus on:

| Key | Signal | Where |
|-----|--------|-------|
| λ Efficiency | "caching", "optimizes" | Commit message |
| π Synthesis | "connects findings", "integrates" | Docstrings |

## Statistics

| Metric | Value |
|--------|-------|
| Total experiments | 0 |
| Kept | 0 |