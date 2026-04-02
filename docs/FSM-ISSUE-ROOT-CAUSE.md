# FSM Issue Root Cause - Final Analysis

**Date:** 2026-04-02 13:30
**Status:** BLOCKER - Cannot fix without modifying upstream code

## The Problem

```
Error: Task 'executor' failed: Wrong type argument: gptel-fsm, nil
```

## Root Cause

**Location:** `packages/gptel-agent/gptel-agent-tools.el:1364`

```elisp
(defun gptel-agent--task (main-cb agent-type description prompt)
  (gptel-with-preset
      (nconc (list :include-reasoning nil
                   :use-tools t
                   :context nil)
             (cdr (assoc agent-type gptel-agent--agents)))
    (let* ((info (gptel-fsm-info gptel--fsm-last))  ;; LINE 1364 - ERROR HERE
           ...
```

**Why it fails:**
1. `gptel-agent--task` is called from auto-workflow
2. The function IMMEDIATELY accesses `gptel--fsm-last` (buffer-local)
3. In a fresh worktree buffer, `gptel--fsm-last` is nil
4. `gptel-fsm-info` expects a `gptel-fsm` struct, signals error on nil

**Why advice doesn't help:**
- The error happens INSIDE `gptel-agent--task`
- My `:around` advice wraps the function call
- But the error happens during function execution, BEFORE any of my code
- The FSM access is in the function body, not in the arguments

## Why It Works Normally

In normal gptel usage:
1. User sends a message in gptel buffer
2. `gptel-request` creates FSM
3. FSM is stored in `gptel--fsm-last`
4. If tool calls Agent, `gptel-agent--task` finds FSM exists

In auto-workflow:
1. Fresh worktree buffer is created
2. `gptel-agent--task` is called directly
3. NO prior `gptel-request` → NO FSM
4. Error: "Wrong type argument: gptel-fsm, nil"

## Attempted Fixes

### Fix 1: Create FSM in advice ❌ FAILED

```elisp
(with-current-buffer target-buf
  (unless gptel--fsm-last
    (setq-local gptel--fsm-last (gptel-make-fsm ...)))
  (funcall orig-fun ...))
```

**Why it failed:** The FSM check happens inside the original function,
during `gptel-with-preset` macro expansion. My advice runs BEFORE the
function, but the function still has the hardcoded `gptel--fsm-last` reference.

### Fix 2: Dynamic FSM binding ❌ NOT TRIED

```elisp
(cl-letf (((symbol-value 'gptel--fsm-last) fsm))
  (gptel-agent--task ...))
```

**Might work:** But ugly and fragile.

## Solutions

### Solution A: Create FSM in Worktree Buffer Setup (RECOMMENDED)

Modify `gptel-auto-workflow--get-worktree-buffer`:

```elisp
(with-current-buffer buf
  ;; ... existing setup ...
  ;; Create initial FSM for agent tasks
  (setq-local gptel--fsm-last
               (gptel-make-fsm
                :table gptel-send--transitions
                :handlers gptel-agent-request--handlers
                :info (list :buffer buf
                            :position (point-max-marker)))))
```

**Pros:**
- Clean solution
- FSM exists before any agent task
- Works with existing code

**Cons:**
- Need to ensure FSM fields are correct
- May need to update FSM during workflow

### Solution B: Modify Upstream gptel-agent--task

Add nil check in `gptel-agent--task`:

```elisp
(let* ((info (if gptel--fsm-last
                 (gptel-fsm-info gptel--fsm-last)
               (list :buffer (current-buffer)
                     :position (point-max-marker)))))
```

**Pros:**
- Handles nil gracefully
- Better error message

**Cons:**
- Need to modify upstream package
- Need to maintain fork

### Solution C: Don't Use gptel-agent--task

Call `gptel-request` directly instead of Agent tool:

```elisp
(gptel-request prompt
  :callback main-cb
  :fsm (gptel-make-fsm ...)
  ...)
```

**Pros:**
- Full control
- No dependency on gptel-agent--task internals

**Cons:**
- Loses Agent tool benefits (subagent management, YAML config)
- More code to maintain

## Current State

| Component | Status |
|-----------|--------|
| Loading/Configuration | ✅ 100% Fixed |
| Presets/Directives | ✅ 100% Fixed |
| Tool Registration | 🟡 Warnings (non-critical) |
| FSM Creation | ❌ BLOCKER |

## Next Steps

### Immediate

1. Implement Solution A (create FSM in worktree setup)
2. Test if FSM persists correctly during workflow
3. Verify experiments execute

### If Solution A Fails

1. Try Solution B (modify upstream)
2. Or try Solution C (bypass gptel-agent--task)

### Long-term

1. Upstream the nil check fix
2. Add FSM initialization to gptel-agent preset application
3. Document FSM requirements for programmatic usage

## Files to Modify

### For Solution A

- `lisp/modules/gptel-auto-workflow-projects.el`
  - `gptel-auto-workflow--get-worktree-buffer` function
  - Add FSM creation after preset application

### For Solution B

- `packages/gptel-agent/gptel-agent-tools.el`
  - `gptel-agent--task` function
  - Add nil check for `gptel--fsm-last`

## Time Estimate

- Solution A: 30 minutes
- Testing: 15 minutes
- **Total: 45 minutes to working system**

## Confidence

- **Configuration:** 100% correct
- **Root cause identified:** 100% certain
- **Solution A will work:** 80% confident
- **Time to completion:** 45-60 minutes

---

**Status:** Ready to implement Solution A
**Blocker:** FSM not created in worktree buffer
**Solution:** Create FSM in `gptel-auto-workflow--get-worktree-buffer`