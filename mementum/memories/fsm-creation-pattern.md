# FSM Creation Pattern for Auto-Workflow

**Date**: 2026-04-02
**Category**: pattern
**Related**: auto-workflow, fsm, buffer-local

## Problem

`gptel-agent--task` accesses `gptel--fsm-last` which is nil in fresh worktree buffers.

**Error**: `Wrong type argument: gptel-fsm, nil`

## Root Cause

In auto-workflow:
1. Fresh worktree buffer created
2. `gptel-agent--task` called directly
3. NO prior `gptel-request` → NO FSM
4. FSM variable is buffer-local, nil in new buffer

In normal usage:
1. User sends message in gptel buffer
2. `gptel-request` creates FSM
3. FSM stored in `gptel--fsm-last`
4. Agent task finds existing FSM

## Solution

Create FSM in worktree buffer setup:

```elisp
(require 'gptel-request)
(require 'gptel-agent-tools)

(setq-local gptel--fsm-last
            (gptel-make-fsm
             :table gptel-send--transitions
             :handlers gptel-agent-request--handlers
             :info (list :buffer (current-buffer)
                         :position (point-max-marker))))
```

## Requirements

1. **Require dependencies first**: `gptel-request`, `gptel-agent-tools`
2. **Set buffer-local**: Use `setq-local` in correct buffer
3. **Proper FSM fields**: `:table`, `:handlers`, `:info`

## Signal

- Agent tasks need FSM in buffer
- FSM is buffer-local variable
- Create FSM before calling agent functions

## Verification

Evidence of success:
```
[FSM-DEBUG] fsm-last before: #s(gptel-fsm INIT ...)
[nucleus] Subagent executor still running... (596.7s elapsed)
```

FSM created successfully, experiments execute.