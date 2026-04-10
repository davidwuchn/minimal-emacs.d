---
title: Auto-Workflow System
status: active
category: knowledge
tags: [auto-workflow, gptel, agent, automation, emacs]
---

# Auto-Workflow System

The auto-workflow is an autonomous AI-driven optimization system for Emacs configurations. It runs unattended, makes decisions independently, and enforces human review before merging changes to production.

## Core Principles

| Principle | Description |
|-----------|-------------|
| **Never Ask** | Auto-workflow never prompts for user input |
| **Branch First** | All changes happen in isolated optimize branches |
| **Human Review** | Only humans can merge to main via PR |
| **Multi-Project** | Supports multiple projects via `.dir-locals.el` |

---

## Branching Strategy

### Branch Format

```
optimize/{target-name}-{hostname}-exp{N}
```

**Example:**
```
optimize/retry-imacpro.taila8bdd.ts.net-exp1
```

### The Rule

```
λ auto-workflow-branching(x).
    change(x) → branch(optimize/{target}-{hostname}-exp{N})
    | push(optimize/...) → origin/optimize/...
    | ¬push(main)
    | human_review → merge(main)
```

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    AUTO-WORKFLOW BRANCHING                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. CREATE WORKTREE                                         │
│     ┌────────────────────┐                                  │
│     │ git worktree add   │                                  │
│     │ ../optimize/...    │                                  │
│     └──────────┬─────────┘                                  │
│                │                                             │
│                ▼                                             │
│  2. EXECUTOR CHANGES                                         │
│     ┌────────────────────┐                                  │
│     │ make changes in    │                                  │
│     │ worktree (isolated)│                                  │
│     └──────────┬─────────┘                                  │
│                │                                             │
│                ▼                                             │
│  3. COMMIT TO OPTIMIZE                                       │
│     ┌────────────────────┐                                  │
│     │ git commit -m "..."│                                  │
│     │ on optimize/...    │                                  │
│     └──────────┬─────────┘                                  │
│                │                                             │
│                ▼                                             │
│  4. PUSH TO origin/optimize/...  ❌ PUSH TO MAIN!           │
│     ┌────────────────────┐                                  │
│     │ git push origin    │                                  │
│     │ optimize/...       │                                  │
│     └──────────┬─────────┘                                  │
│                │                                             │
│                ▼                                             │
│  5. HUMAN REVIEW → PR → MERGE                               │
│     ┌────────────────────┐                                  │
│     │ Create PR, review, │                                  │
│     │ merge to main       │                                  │
│     └────────────────────┘                                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Implementation

**Code Location:** `gptel-tools-agent.el:1134`

```elisp
(when gptel-auto-experiment-auto-push
  (magit-git-success "push" "origin" gptel-auto-workflow--current-branch))
```

**Critical Rule:** Never push directly to main. Always push to `origin optimize/...`.

### Common Mistake

```bash
# ❌ WRONG - This violates branching rule
git push origin main

# ✅ CORRECT - Push to optimize branch
git push origin optimize/retry-imacpro.taila8bdd.ts.net-exp1
```

---

## Autonomy Principle

### The Principle

```
λ autonomous(x).
    fail(x) → retry(x)
    | retry(x) → retry(x)
    | max_retries → log_and_continue
    | ¬ask(user)
    | ¬stop_for_input
```

Auto-workflow is fully autonomous. It never asks the user for confirmation, input, decision, or clarification.

### What This Means

| Don't Do This | Do This Instead |
|---------------|-----------------|
| `y-or-n-p` "Retry?" | Retry automatically |
| `yes-or-no-p` "Continue?" | Log and continue |
| `read-from-minibuffer` | Use fallback values |
| `completing-read` | Use default configuration |
| `user-error` (for recoverable) | Log and retry |

### Retry Pattern

```elisp
(defun gptel-auto-workflow-with-retry (fn max-retries)
  "Call FN with automatic retry, never ask user."
  (let ((attempts 0)
        (last-error nil))
    (while (< attempts max-retries)
      (cl-incf attempts)
      (condition-case err
          (funcall fn)  ; Try the operation
        (error
         (setq last-error err)
         (when (< attempts max-retries)
           (message "Attempt %d/%d failed: %s"
                    attempts max-retries (error-message-string err))
           (sit-for 1))))  ; Brief pause before retry
         ;; If we exit loop without success, log the last error
    (when last-error
      (gptel-auto-workflow-log-error last-error))))
```

### Failure Handling Matrix

| Failure Type | Auto-Response |
|--------------|----------------|
| Worktree create fails | Retry with exponential backoff |
| Test fails | Log score, continue to next target |
| LLM timeout | Retry with shorter prompt |
| Push fails | Retry with fresh auth |
| Buffer killed | Restore from saved state |

---

## Multi-Project Configuration

### Problem

Original auto-workflow was hardcoded for single project (`~/.emacs.d`).

### Solution: `.dir-locals.el`

Use Emacs' built-in `.dir-locals.el` mechanism for per-project configuration.

### Detection Priority

`gptel-auto-workflow--project-root` checks in order:

1. **Override variable** (from `.dir-locals.el`)
   - `gptel-auto-workflow--project-root-override`
2. **Git root** (auto-detected)
   - `git rev-parse --show-toplevel`
3. **Fallback**
   - `~/.emacs.d/`

### Configuration Example

Create `.dir-locals.el` in project root:

```elisp
((nil
  . ((gptel-auto-workflow--project-root-override . "/path/to/project")
     (gptel-auto-workflow-targets . ("src/main.el" "src/utils.el"))
     (gptel-auto-experiment-max-per-target . 5)
     (gptel-auto-experiment-time-budget . 1200)
     (gptel-backend . gptel--dashscope)
     (gptel-model . qwen3.5-plus))))
```

### Git vs Non-Git Projects

**For Git Projects:**
```elisp
((nil
  . ((gptel-auto-workflow-targets . ("src/config.el" "src/init.el")))))
```
- Git root auto-detected - no override needed

**For Non-Git Projects:**
```elisp
((nil
  . ((gptel-auto-workflow--project-root-override . "/home/user/my-config")
     (gptel-auto-workflow-targets . ("init.el" "packages.el")))))
```
- Must set override to absolute path

### Manual Project Switching

```elisp
M-x gptel-auto-workflow-set-project-root
```

---

## Session Architecture

Each experiment runs in its own Git worktree:

```
┌─────────────────────────────────────────────────────────────┐
│  WORKTREE: optimize/target-exp1                             │
│  (default-directory: /path/to/worktree)                     │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐            │
│  │  analyzer   │ │  executor   │ │   grader    │            │
│  │  subagent   │ │  subagent   │ │  subagent   │            │
│  └─────────────┘ └─────────────┘ └─────────────┘            │
│  All subagents share worktree context                        │
└─────────────────────────────────────────────────────────────┘
```

**Key Points:**
- Each worktree has isolated context
- All subagents within worktree share `default-directory`
- Multiple machines can optimize same target without conflicts

---

## Known Issues and Fixes

### Bug: Deleted Buffer Error

**Discovery:** During e2e test, auto-workflow fails with "Selecting deleted buffer" error.

**Symptoms:**
- Project buffer `*gptel-agent:.emacs.d*` gets deleted during execution
- Executor runs for 560s+ without completing changes
- No results logged to TSV file
- Error: `gptel callback error: (error "Selecting deleted buffer")`

**Root Cause:**
The `gptel-auto-workflow--advice-task-override` advice overrides `current-buffer` to return a fixed project buffer. If that buffer is killed during async execution, all callbacks fail.

**Fix Applied:**

```elisp
;; 1. Protect buffer from being killed during runs
(defun gptel-auto-workflow-protect-buffer (buffer)
  "Add BUFFER to kill-buffer-query-functions protection."
  (add-hook 'kill-buffer-query-functions
            (lambda () (not (eq buffer (current-buffer)))) nil t))

;; 2. Check buffer liveness each call, fallback if killed
(defun gptel-auto-workflow-safe-current-buffer ()
  "Return project buffer or fallback if killed."
  (if (buffer-live-p gptel-auto-workflow--project-buffer)
      gptel-auto-workflow--project-buffer
    (buffer-local-value 'default-directory
                        (get-buffer-create " *gptel-agent:fallback*"))))

;; 3. Save original function before overriding to avoid recursion
(defvar gptel-auto-workflow--original-current-buffer (symbol-function 'current-buffer))
```

**Result:**
- E2E test passed - experiment completed in 230s with `kept` decision
- Score improved: 0.40 → 0.41
- Commit `bae1b73` merged to staging

---

## Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `gptel-auto-workflow--project-root-override` | `nil` | Override project root path |
| `gptel-auto-workflow-targets` | `nil` | List of files to optimize |
| `gptel-auto-experiment-max-per-target` | `5` | Max experiments per target |
| `gptel-auto-experiment-time-budget` | `3600` | Time budget in seconds |
| `gptel-auto-experiment-auto-push` | `t` | Auto-push to remote |
| `gptel-backend` | `gptel--dashscope` | LLM backend to use |
| `gptel-model` | `qwen3.5-plus` | Model name |

---

## Related

- [GPTel Agent](./gptel-agent.md) - Main AI agent framework
- [Git Worktrees](./git-worktrees.md) - Branch isolation mechanism
- [Dir Locals](./dir-locals.md) - Per-directory Emacs settings
- [Retry Patterns](./retry-patterns.md) - Error handling strategies
- [Subagents](./subagents.md) - Analyzer, executor, grader agents

---

## Quick Reference Commands

```elisp
;; Start auto-workflow
M-x gptel-auto-workflow

;; Set project root manually
M-x gptel-auto-workflow-set-project-root

;; Check current configuration
M-x gptel-auto-workflow-show-config

;; View experiment logs
M-x gptel-auto-workflow-logs
```

---

*Last updated: 2026-03-28*