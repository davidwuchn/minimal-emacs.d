# Buffer-Local Callback Context Bug

## Issue
Workflow gets stuck because buffer-local variables (`my/gptel--agent-task-done`, `gptel-auto-experiment--grade-done`) are accessed in wrong buffer context when callbacks fire.

## Root Cause
1. Variables defined with `defvar-local` or `make-variable-buffer-local`
2. Callbacks from `gptel-agent--task` fire in arbitrary buffer context
3. `setq` and `unless` checks happen in wrong buffer

## Evidence
- `gptel-auto-experiment--grade-done=t` found in `*Minibuf-1*` (emacsclient buffer)
- `gptel-auto-experiment--grade-done=nil` in worktree buffer
- 5 timeout messages, only 1 result recorded

## Fix Required
Wrap all buffer-local variable access in `with-current-buffer origin-buf`:

1. **my/gptel--agent-task-with-timeout** (line 626):
   - Move `setq` initializations after `let*` captures `origin-buf`
   - Wrap in `(with-current-buffer origin-buf ...)`
   - Wrap wrapped-cb body in `with-current-buffer`

2. **gptel-auto-experiment-grade** (line 1595):
   - Capture `origin-buf` at start
   - Wrap `setq` and timer callbacks in `with-current-buffer`

## Files
- `lisp/modules/gptel-tools-agent.el`
- Lines 617-625 (defvar-local declarations)
- Lines 626-691 (my/gptel--agent-task-with-timeout)
- Lines 1595-1634 (gptel-auto-experiment-grade)

## Status
Identified 2026-03-28, fix pending (paren balancing issues in edit)