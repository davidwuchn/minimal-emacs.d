---
title: auto
status: open
---

Synthesized from 4 memories.

# Auto-Workflow Branching Rule

**Date**: 2026-03-25
**Symbol**: 🔁 pattern

## Rule

```
λ auto-workflow-branching(x).
    change(x) → branch(optimize/{target}-{hostname}-exp{N})
    | push(optimize/...) → origin/optimize/...
    | ¬push(main)
    | human_review → merge(main)
```

## Branch Format

`optimize/{target-name}-{hostname}-exp{N}`

**Example**: `optimize/retry-imacpro.taila8bdd.ts.net-exp1`

## Flow

1. Create worktree with optimize branch
2. Executor makes changes in worktree (isolated from main)
3. If improvement → commit to optimize branch
4. Push to `origin optimize/...` (NOT main!)
5. Human reviews and merges to main via PR

## Why This Matters

- Prevents unreviewed AI changes on main
- Multiple machines can optimize same target without conflicts
- Human gate for quality control

## Code Location

`gptel-tools-agent.el:1134`:
```elisp
(when gptel-auto-experiment-auto-push
  (magit-git-success "push" "origin" gptel-auto-workflow--current-branch))
```

## Lesson Learned

On 2026-03-25, I mistakenly pushed auto-workflow changes directly to main.
This violated the branching rule. Always check branch before pushing.

# Auto-Workflow E2E Bug: Deleted Buffer

**Discovery:** During e2e test, auto-workflow fails with "Selecting deleted buffer" error.

**Symptoms:**
- Project buffer `*gptel-agent:.emacs.d*` gets deleted during execution
- Executor runs for 560s+ without completing changes
- No results logged to TSV file
- Error: `gptel callback error: (error "Selecting deleted buffer")`

**Root Cause:**
The `gptel-auto-workflow--advice-task-override` advice overrides `current-buffer` to return a fixed project buffer. If that buffer is killed during async execution, all callbacks fail.

**Fix Applied:**
1. Added `kill-buffer-query-functions` protection to prevent buffer kill during runs
2. Made `current-buffer` override check liveness each call, fall back if killed
3. Saved original `current-buffer` function before overriding to avoid recursion

**Result:**
- E2E test passed - experiment completed in 230s with `kept` decision
- Score improved: 0.40 → 0.41
- Commit `bae1b73` merged to staging

**Symbol:** ✅ (fixed)

---
title: Auto-Workflow Never Asks
created: 2026-03-25
tags: [auto-workflow, principle, autonomy, resilience]
---

# Auto-Workflow Never Asks User

## The Principle

```
λ autonomous(x).
    fail(x) → retry(x)
    | retry(x) → retry(x)
    | max_retries → log_and_continue
    | ¬ask(user)
    | ¬stop_for_input
```

## What This Means

Auto-workflow is fully autonomous. It never asks the user for:
- Confirmation
- Input
- Decision
- Clarification

Instead, it:
1. Tries again (retry)
2. Tries differently (alternative approach)
3. Logs the failure and continues

## Retry Pattern

```elisp
(defun with-retry (fn max-retries)
  "Call FN, retry on failure, never ask user."
  (let ((attempts 0))
    (while (< attempts max-retries)
      (cl-incf attempts)
      (condition-case err
          (funcall fn)  ; Try
        (error
         (when (< attempts max-retries)
           (sit-for 1)))))))  ; Brief pause, then retry
```

## Examples

| Failure | Don't Do This | Do This |
|---------|---------------|---------|
| Worktree create fails | Ask user "Retry?" | Retry automatically |
| Test fails | Ask "Continue?" | Log and continue to next target |
| LLM timeout | Ask "What now?" | Retry with shorter prompt |
| Push fails | Ask "Force push?" | Retry with fresh auth |

## Why This Matters

- Auto-workflow runs at 2 AM unattended
- No human is watching to answer questions
- Each failure is an opportunity to try again
- Eventual success > immediate failure

## The Rule

**Never use in auto-workflow:**
- `y-or-n-p`
- `yes-or-no-p`
- `read-from-minibuffer`
- `completing-read`
- `user-error` (for recoverable issues)

**Always use instead:**
- Retry logic
- Fallback paths
- Error logging
- Continue to next task

# Multi-Project Auto-Workflow via .dir-locals.el

**Date:** 2026-03-28  
**Approach:** Option B - Repository-level configuration using standard Emacs mechanisms

## Problem

Original auto-workflow was hardcoded for single project (`~/.emacs.d`).

## Solution

Use Emacs' built-in `.dir-locals.el` mechanism for per-project configuration.

## How It Works

### 1. Project Detection Priority

`gptel-auto-workflow--project-root` now checks in order:

1. **Override variable** (from .dir-locals.el)
   - `gptel-auto-workflow--project-root-override`
2. **Git root** (auto-detected)
   - `git rev-parse --show-toplevel`
3. **Fallback**
   - `~/.emacs.d/`

### 2. Configuration via .dir-locals.el

Place `.dir-locals.el` in project root:

```elisp
((nil
  . ((gptel-auto-workflow--project-root-override . "/path/to/project")
     (gptel-auto-workflow-targets . ("src/main.el" "src/utils.el"))
     (gptel-auto-experiment-max-per-target . 5)
     (gptel-auto-experiment-time-budget . 1200)
     (gptel-backend . gptel--dashscope)
     (gptel-model . qwen3.5-plus))))
```

### 3. Benefits

- **Standard Emacs mechanism** - No custom loading code
- **Automatic loading** - Loaded when visiting any file in project
- **Per-project isolation** - Each project has its own targets and settings
- **Git or non-git** - Works with any directory structure

## Usage

### For Git Projects

1. Create `.dir-locals.el` in project root
2. Set `gptel-auto-workflow-targets` for that project
3. Auto-workflow will use git root automatically

### For Non-Git Projects

1. Create `.dir-locals.el` in project root
2. Set `gptel-auto-workflow--project-root-override` to absolute path
3. Auto-workflow will use that path instead of git detection

### Manual Switching

```elisp
M-x gptel-auto-workflow-set-project-root
```

## Files Changed

- `lisp/modules/gptel-tools-agent.el` - Updated project detection
- `.dir-locals.el` - Example configuration

## Session Architecture (Per Worktree)

```
┌─────────────────────────────────────────────────────────┐
│  WORKTREE: optimize/target-exp1                         │
│  (default-directory: worktree path)                     │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐       │
│  │  analyzer   │ │  executor   │ │   grader    │       │
│  │  subagent   │ │  subagent   │ │  subagent   │       │
│  └─────────────┘ └─────────────┘ └─────────────┘       │
│  All share worktree context                             │
└─────────────────────────────────────────────────────────┘
```

Each experiment worktree has its own context, and all subagents within that worktree share the same `default-directory`.

## Future Improvements

- Add `M-x gptel-auto-workflow-switch-project` for interactive switching
- Per-project cron jobs (currently all use ~/.emacs.d/)
- Project-specific agent directories
