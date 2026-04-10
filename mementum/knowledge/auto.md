---
title: Auto-Workflow System
status: active
category: knowledge
tags: [auto-workflow, gptel, emacs, automation, agent]
---

# Auto-Workflow System

The auto-workflow system enables autonomous AI-driven code improvement using gptel agents. It operates unattended, running experiments on targets, analyzing results, and proposing improvements without human intervention until merge time.

## Branching Strategy

### The Rule

```
λ auto-workflow-branching(x).
    change(x) → branch(optimize/{target}-{hostname}-exp{N})
    | push(optimize/...) → origin/optimize/...
    | ¬push(main)
    | human_review → merge(main)
```

### Branch Format

`optimize/{target-name}-{hostname}-exp{N}`

**Examples**:

| Branch Name | Target | Hostname | Experiment Number |
|-------------|--------|----------|-------------------|
| `optimize/retry-imacpro.taila8bdd.ts.net-exp1` | retry | imacpro.taila8bdd.ts.net | 1 |
| `optimize/utils-imacpro.taila8bdd.ts.net-exp2` | utils | imacpro.taila8bdd.ts.net | 2 |
| `optimize/config-linux.example.com-exp3` | config | linux.example.com | 3 |

### Workflow Flow

1. **Create worktree**: Spawn `optimize/{target}-{hostname}-exp{N}` from main
2. **Execute changes**: Executor works in isolated worktree (not main)
3. **Commit improvements**: If improvement found, commit to optimize branch
4. **Push to origin**: Push to `origin optimize/...` (NEVER directly to main!)
5. **Human review**: Merge to main via PR

### Critical Warning

**Never push directly to main from auto-workflow!**

```elisp
;; WRONG - This violates branching rule
(magit-git-success "push" "origin" "main")

;; CORRECT - Push to optimize branch
(magit-git-success "push" "origin" gptel-auto-workflow--current-branch)
```

The code location for auto-push is in `gptel-tools-agent.el:1134`:

```elisp
(when gptel-auto-experiment-auto-push
  (magit-git-success "push" "origin" gptel-auto-workflow--current-branch))
```

### Why This Matters

- Prevents unreviewed AI changes on main
- Multiple machines can optimize same target without conflicts
- Human gate maintains quality control

---

## The "Never Ask" Principle

### The Core Rule

```
λ autonomous(x).
    fail(x) → retry(x)
    | retry(x) → retry(x)
    | max_retries → log_and_continue
    | ¬ask(user)
    | ¬stop_for_input
```

### What This Means

Auto-workflow operates **fully autonomously**. It never prompts the user for:

- Confirmation
- Input
- Decision
- Clarification

Instead, it employs retry logic, alternative approaches, and error logging.

### Retry Pattern Implementation

```elisp
(defun with-retry (fn max-retries &optional delay)
  "Call FN, retry on failure, never ask user.
MAX-RETRY attempts with optional DELAY (seconds) between attempts."
  (let ((attempts 0)
        (delay (or delay 1)))
    (while (< attempts max-retries)
      (cl-incf attempts)
      (condition-case err
          (funcall fn)  ; Try the operation
        (error
         (message "[Auto-Workflow] Attempt %d/%d failed: %s"
                  attempts max-retries (error-message-string err))
         (when (< attempts max-retries)
           (sit-for delay)  ; Brief pause, then retry
           (setq attempts (1+ attempts))))))))
```

### Failure Handling Matrix

| Failure Scenario | ❌ Don't Do This | ✅ Do This |
|-----------------|------------------|------------|
| Worktree create fails | "Retry?" prompt | Automatic retry |
| Test fails | "Continue?" prompt | Log and continue |
| LLM timeout | "What now?" prompt | Retry with shorter prompt |
| Push fails | "Force push?" prompt | Retry with fresh auth |
| Buffer killed | "Restore?" prompt | Fallback to saved original |

### Prohibited Functions

**Never use in auto-workflow context:**

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

### Why This Matters

- Auto-workflow runs unattended (2 AM, weekends)
- No human present to answer questions
- Each failure is an opportunity to retry
- Eventual success > immediate failure

---

## Multi-Project Configuration

### Problem

Original auto-workflow was hardcoded for single project (`~/.emacs.d`).

### Solution: .dir-locals.el

Use Emacs' built-in `.dir-locals.el` mechanism for per-project configuration.

### Project Detection Priority

`gptel-auto-workflow--project-root` checks in this order:

1. **Override variable** (from .dir-locals.el)
   - `gptel-auto-workflow--project-root-override`
2. **Git root** (auto-detected)
   - `git rev-parse --show-toplevel`
3. **Fallback**
   - `~/.emacs.d/`

### Configuration Example

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

### Usage Patterns

#### For Git Projects

1. Create `.dir-locals.el` in project root
2. Set `gptel-auto-workflow-targets` for that project
3. Auto-workflow uses git root automatically

#### For Non-Git Projects

1. Create `.dir-locals.el` in project root
2. Set `gptel-auto-workflow--project-root-override` to absolute path
3. Auto-workflow uses that path instead of git detection

#### Manual Switching

```elisp
M-x gptel-auto-workflow-set-project-root
```

### Session Architecture (Per Worktree)

```
┌─────────────────────────────────────────────────────────┐
│  WORKTREE: optimize/target-exp1                         │
│  (default-directory: worktree path)                    │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐       │
│  │  analyzer   │ │  executor   │ │   grader    │       │
│  │  subagent   │ │  subagent   │ │  subagent   │       │
│  └─────────────┘ └─────────────┘ └─────────────┘       │
│  All share worktree context                             │
└─────────────────────────────────────────────────────────┘
```

Each experiment worktree has its own context. All subagents within that worktree share the same `default-directory`.

---

## E2E Bug: Deleted Buffer

### Discovery

During E2E testing, auto-workflow fails with "Selecting deleted buffer" error.

### Symptoms

- Project buffer `*gptel-agent:.emacs.d*` gets deleted during execution
- Executor runs for 560s+ without completing changes
- No results logged to TSV file
- Error: `gptel callback error: (error "Selecting deleted buffer")`

### Root Cause

The `gptel-auto-workflow--advice-task-override` advice overrides `current-buffer` to return a fixed project buffer. If that buffer is killed during async execution, all callbacks fail.

### Fix Applied

1. Added `kill-buffer-query-functions` protection to prevent buffer kill during runs
2. Made `current-buffer` override check liveness each call, fall back if killed
3. Saved original `current-buffer` function before overriding to avoid recursion

```elisp
;; Before (broken)
(defun gptel-auto-workflow--advice-task-override (orig-fun &rest args)
  "Override current-buffer to return project buffer."
  (set-buffer (gptel-auto-workflow--get-project-buffer))
  (apply orig-fun args))

;; After (fixed)
(defun gptel-auto-workflow--advice-task-override (orig-fun &rest args)
  "Override current-buffer, checking liveness each call."
  (let ((buf (gptel-auto-workflow--get-project-buffer)))
    (when (buffer-live-p buf)
      (set-buffer buf)
      (apply orig-fun args))))
```

### Result

- E2E test passed - experiment completed in 230s with `kept` decision
- Score improved: 0.40 → 0.41
- Commit `bae1b73` merged to staging

---

## Key Variables Reference

| Variable | Purpose | Default |
|----------|---------|---------|
| `gptel-auto-workflow--project-root-override` | Manual project path override | `nil` |
| `gptel-auto-workflow-targets` | List of files to optimize | `nil` |
| `gptel-auto-experiment-max-per-target` | Max experiments per target | `5` |
| `gptel-auto-experiment-time-budget` | Time budget in seconds | `3600` |
| `gptel-auto-experiment-auto-push` | Auto-push to origin | `t` |
| `gptel-backend` | LLM backend to use | `gptel--dashscope` |
| `gptel-model` | Model name | `qwen3.5-plus` |

---

## Related

- [gptel-agent](gptel-agent.html) - The agent system powering auto-workflow
- [worktree-management](worktree-management.html) - Git worktree operations
- [emacs-async](emacs-async.html) - Async execution patterns
- [dir-locals](dir-locals.html) - Emacs directory local variables

---