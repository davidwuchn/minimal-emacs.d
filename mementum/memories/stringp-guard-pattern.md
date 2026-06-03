# Stringp Guard Pattern

**Context**: `gptel-tools-agent-experiment-core.el` — `gptel-auto-experiment--validate-all-modified-files`

**Change**: Added `(stringp file)` guard before `(string-suffix-p ".el" file)` in the `dolist` loop.

**Why**: `file` comes from `split-string` with `omit-nulls=t`, but source data (git diff output) can produce unexpected results in edge cases. Without the guard, a nil `file` would cause `wrong-type-argument stringp nil` error.

**Pattern**: This is a general safety pattern — before calling `string-suffix-p`, `string-match-p`, or `string=` on values derived from external commands, add a `(stringp x)` guard.

**Eight Keys**:
- ∀ Vigilance: edge case handled (nil file from split-string)
- φ Vitality: builds on defensive programming pattern