---
title: "String Guard Pattern"
status: active
category: pattern
tags: [string, safety, elisp, defensive-programming]
related: [nil-guard-pattern, workspace-boundary-pattern]
depends-on: []
---

# String Guard Pattern

> **Frequency**: High (>=3 sessions)
> **Severity**: Medium
> **Applies to**: Functions that process git diff output, file paths, user input

## Problem

`string-suffix-p`, `string-match-p`, `string=` throw `wrong-type-argument stringp nil` when passed nil.

## Root Cause

Values from `split-string` with `omit-nulls=t` can still produce nil in edge cases (empty strings, malformed input).

## Solution: String Guard Pattern

```elisp
;; BEFORE: crashes on nil file
(string-suffix-p ".el" file)         ; wrong-type-argument stringp nil

;; AFTER: safe with guard
(when (stringp file)
  (string-suffix-p ".el" file))
```

## Common Guard Combinations

### File Extension Check
```elisp
(when (and (stringp file) (string-suffix-p ".el" file))
  (process-el-file file))
```

### Path Validation
```elisp
(when (and (stringp path) (file-exists-p path))
  (read-file path))
```

### Git Diff Output
```elisp
(dolist (file (split-string diff-output "\n" t))
  (when (stringp file)
    (process-modified-file file)))
```

## Where to Apply

| Module | Function | Guard Type |
|--------|----------|------------|
| tools-agent-experiment-core.el | gptel-auto-experiment--validate-all-modified-files | stringp |
| tools-agent-git.el | gptel-auto-workflow--get-modified-files | stringp |
| tools-agent-main.el | gptel-auto-workflow--run-async | stringp + numberp |

## Prevention

- Always use `(stringp x)` before string operations
- Use `(and (stringp x) (not (string-empty-p x)))` for non-empty strings
- Validate input from external commands before processing

## References

- `mementum/memories/stringp-guard-pattern.md`
- `mementum/memories/stringp-guard-consistency.md`
- `mementum/memories/nil-guard-stringp-pattern.md`
