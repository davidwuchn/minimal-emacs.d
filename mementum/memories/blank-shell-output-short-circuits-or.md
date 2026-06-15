# Blank Shell Output Short-Circuits `or`

**Date**: 2026-06-15
**Category**: anti-pattern
**Related**: clojure, babashka, fallback, nil-guard-pattern

## Insight

Shell helpers often return `""` on command-not-found or other empty-output cases. In Clojure, `""` is truthy, so `(or "" fallback)` stops early and hides later candidates.

## Fix

Normalize blank stdout to `nil` before fallback chains:

```clojure
(when (not (str/blank? out))
  out)
```

or equivalent `some`/`when-let` handling.

## Test pattern

Stub the shell command to return `""` and stub file existence per branch so each fallback path is isolated. Assert the exact resolved path, not just that the result is non-blank.
