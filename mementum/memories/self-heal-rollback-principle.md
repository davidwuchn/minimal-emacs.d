---
title: Self-Heal Paren-Balance Rollback
date: 2026-06-04
symbol: 💡
---

Self-heal fixers can break paren balance silently. Every fixer must verify
parens after running and revert if broken — this is the "rollback" principle.

## Root Cause
Mechanical fixers (let->let*, remove-binding, rename-var) change paren counts
but never verified the file was still balanced after. A fixer would report
"N fixes" but silently leave depth>0. Subsequent fixers then operated on
broken parse state, compounding damage.

## The Rollback Fix
`gptel-auto-workflow--run-fixer-with-rollback` wraps each fixer:
1. Record paren state before fixer
2. Run fixer
3. Check parens after — if broken, revert file and return 0
4. If file was already broken and fixer didn't help, keep changes

## Key Patterns
- Removing a `let` binding removes `(` AND shifts the `)` on bindings line
- `let->let*` adds 1 char but doesn't change paren count (safe)
- `condition-case` rewrites are highest-risk (multi-level nesting)
- ALWAYS verify after EVERY edit, not at the end
- `check-parens` in `emacs-lisp-mode` is the oracle — trust it

## Diagnostic
Depth>0 at EOF means a form didn't close. Trace from the last
top-level boundary (`depth 0->1` transition) to find the unclosed form.
