## Cache Coherency: `equal` vs `eq` for List Comparison

When caching based on a list variable that may be mutated in-place (via `push`, `setcar`, `nconc`), use `equal` for cache key comparison, not `eq`.

**Bug pattern:**
```elisp
;; WRONG: eq only checks identity, misses in-place mutations
(when (eq cached-key current-list) ...)
```

**Fix:**
```elisp
;; CORRECT: equal checks structural equality
(when (equal cached-key current-list) ...)
```

**Why:** `push` modifies the list in place (same cons cell identity), so `eq` returns t even though contents changed. `equal` compares actual list contents.

**Applies to:** Any cache keyed on mutable lists in Emacs Lisp.
**Evidence:** gptel-auto-workflow--normalized-projects cache missed `push` mutations.