---
title: Grep Before Edit
φ: 0.75
e: grep-before-edit
λ: before.editing.code
Δ: 0.04
evidence: 6
---

💡 Always search with Grep before using Edit to understand context.

## Action
1. Use `grep` to find all occurrences
2. Use `read` to examine context
3. Confirm scope before editing
4. Use `edit` with explicit oldString (not replaceAll unless intentional)

## Why
Prevents:
- **Incomplete changes** - missing related code
- **Unintended modifications** - editing wrong occurrences
- **Context blindness** - editing without understanding
- **Reverts** - discovering incomplete edits later

## When
- Before using Edit tool
- Refactoring or renaming
- Fixing bugs that might occur elsewhere
- Changing function signatures or APIs

## Context
- Applies to: All file editing operations
- Avoid for: Trivial one-line changes in small files
- Related: context-aware, verify-intent