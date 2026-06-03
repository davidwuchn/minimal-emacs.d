---
title: Worktree Safety Guards — Phase 4 Complete
created: 2026-06-03
tags: [worktree, safety, boundary, dual-mayor]
---

## Problem

Edit tools can leak into mayor checkout, contaminating the main branch with
experiment artifacts or breaking the system.

## Solution: Three-Layer Defense

### Layer 1: Prompt Instruction
**File:** `assistant/skills/auto-workflow/prompt-template.md`

Added WORKTREE SAFETY section to executor prompt:
- Verify worktree before EVERY edit
- NEVER edit files outside worktree
- NEVER run git stash/checkout/reset/clean
- NEVER delete files with rm/unlink
- ONLY use Edit/Write/ApplyPatch on worktree files
- ABORT if path looks wrong

### Layer 2: Post-Edit Validation
**File:** `lisp/modules/gptel-tools-agent-experiment-core.el`

`validate-all-modified-files` now checks:
- Each modified file is inside the worktree (`file-in-directory-p`)
- Throws `validation-error` if file is outside worktree
- Logs: "WORKTREE BOUNDARY VIOLATION"

### Layer 3: Pre-Commit Hook
**File:** `.git/hooks/pre-commit`

Prevents commits from mayor checkout if files:
- Contain worktree path indicators (`var/tmp/experiments/`)
- Look like temporary/experiment files (`.tmp`, `.bak`, `experiment-`)

## Tests

2149 tests, 2097 expected, 0 unexpected, 52 skipped — all pass.

## Next Steps

Phase 5: Cross-Mayor Communication (Bead Protocol)
- GTM → PMF beads: research findings → experiment ideas
- PMF → GTM beads: experiment results → validated learnings
