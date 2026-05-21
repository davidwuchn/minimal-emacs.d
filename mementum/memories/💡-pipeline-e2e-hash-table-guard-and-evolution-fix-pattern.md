---
title: "Pipeline E2E: Hash-table guard + evolution-fix pattern"
category: "bug-fix"
tags: ["pipeline", "daemon", "hash-table", "evolution", "defun-redefinition"]
related: ["💡-lisp-modules-gptel-tools-agent-el-adding--bound-and-true-p--.md"]
---

## Problem

Auto-workflow daemon crashed with `(wrong-type-argument hash-table-p nil)` during `run-all-projects` because `gptel-auto-workflow--normalized-projects` tried to `maphash` over a nil hash-table.

## Root Cause

`gptel-auto-workflow--ensure-buffer-tables` reinitializes nil hash-tables, but it was NOT called at the `run-all-projects` entry point. Jobs queued before table initialization caused the crash.

## Fix

Call `(gptel-auto-workflow--ensure-buffer-tables)` at the very beginning of `run-all-projects`, before any `maphash` or table access.

## Secondary Fix: Fragile Paren Structure

`evolution.el` (4047 lines) had unbalanced parens at line 2127: 6 consecutive `)` closed the outer `let*` prematurely, placing cleanup logging variables (`pruned`, `removed-worktrees`, `cleaned-temp`) outside their binding scope → `void-variable pruned`.

**Approach**: Instead of editing the fragile 4047-line file directly, create `gptel-auto-workflow-evolution-fix.el` that redefines ONLY the problematic function after `evolution.el` loads. This avoids:
- Accidentally breaking other paren structures
- Introducing new syntax errors in experiments
- Diff noise in large files

## Policy

- NEVER force-push. Origin force-pushed during distributed pipeline execution. Recovery: `fetch --all` → `rebase` → `push`.
- Auto-generated artifacts (DIRECTIVE.md, strategy-guidance.json) cause merge conflicts during auto-promote. Revert them unless explicitly asked.
