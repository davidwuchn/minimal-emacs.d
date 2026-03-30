💡 experiment-flow-else-branch-bug

## Problem
Experiments showed `verification-failed` then `kept: t` inconsistency. The staging worktree creation failed with "a branch named 'staging' already exists".

## Root Cause 1: Missing else branch
```elisp
(if (not passed)
    ;; then - fail
    ...)
(let ...)  ;; ALWAYS runs - should be in else branch!
```

The `let` for the success path was a sibling of the `if`, not its else branch.

## Root Cause 2: Wrong magit function
`magit-worktree-branch` creates NEW branches and fails if branch exists.
`magit-worktree-checkout` checks out an existing branch in a new worktree.

Staging branch always exists, so `magit-worktree-branch` always failed.

## Fix
1. Add proper else branch for `(if (not passed) ...)`
2. Use `magit-worktree-checkout` for staging worktree

## Key Insight
In Elisp, `if` with multiple forms in then branch needs `progn`, but else branch is a single form. Multiple forms in else need `progn` too. The indentation was misleading - check the actual parentheses structure.

## Files
- lisp/modules/gptel-tools-agent.el:2396 - else branch fix
- lisp/modules/gptel-tools-agent.el:1237 - magit-worktree-checkout