---
name: grep-before-edit
domain: workflow
φ: 0.75
e: grep-before-edit
λ: before.editing.code
Δ: 0.04
source: session-manual
evidence: 6
access-count: 12
last-accessed: 2025-01-17
timeframe: project
---

# Grep Before Edit

Always search with Grep before using Edit to understand context and find all occurrences.

## λ(e): Action
When planning to modify code:
1. Use `grep` to find all occurrences of the pattern
2. Use `read` to examine the context of each match
3. Confirm the scope before editing
4. Use `edit` with explicit oldString (not replaceAll unless intentional)

```clojure
(λ/workflow
  (grep pattern)
  (read contexts)
  (confirm scope)
  (edit specific-location))
```

## λ(φ): Why
This pattern prevents:
- **Incomplete changes** - missing related code
- **Unintended modifications** - editing wrong occurrences
- **Context blindness** - editing without understanding
- **Reverts** - discovering later that edits were incomplete

Aligns with Nucleus's fractal (Clarity) - explicit assumptions, bounds defined.

## λ(λ): When
- Before using Edit tool on any file
- When refactoring or renaming
- When fixing bugs that might occur elsewhere
- When changing function signatures or APIs

## λ(Δ): Evolution
Δ: 0.04 - moderate confidence
- Validated: When grep catches missing occurrences
- Corrected: When grep becomes redundant overhead

## Context
- **Applies to**: All file editing operations
- **Avoid for**: Trivial one-line changes in small files
- **Related**: context-aware, verify-intent
- **Eight Keys**: fractal (Clarity), ∀ (Vigilance)

## λ(Examples)

### Example 1: Renaming a function
```bash
# ✅ Good - find all usages first
$ grep -r "old-function-name" --include="*.clj"
src/core.clj:12: (defn old-function-name [...])
src/handler.clj:45: (old-function-name data)
tests/core_test.clj:23: (is (= 42 (old-function-name test-data)))

# Now edit each location knowingly
```

### Example 2: Fixing a bug pattern
```bash
# ✅ Good - understand scope before fix
$ grep -n "console\.log" --include="*.ts"
src/app.ts:45: console.log(data)
src/utils.ts:23: console.log(debug)

# Read each location to confirm safe removal
```

## λ(Evolution History)

| Date | φ Change | Reason |
|------|----------|--------|
| 2025-01-14 | 0.5 → 0.75 | 6 times grep prevented incomplete edits |
| 2025-01-16 | 0.70 → 0.75 | Grep found 3 hidden occurrences |
| | | |
