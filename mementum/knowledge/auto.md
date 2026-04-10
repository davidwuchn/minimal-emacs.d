---
title: Auto-Workflow System
status: active
category: knowledge
tags: [auto-workflow, autonomous, gptel, emacs-ai, branching, experimentation]
---

# Auto-Workflow System

The auto-workflow system enables autonomous AI-driven code optimization in Emacs. It runs unattended, makes decisions without human input, and manages its own branching and experimentation workflow.

## Branching Architecture

### The Branching Rule

All auto-workflow experiments operate on isolated branches following a strict naming convention:

```
optimize/{target-name}-{hostname}-exp{N}
```

**Example Branch Names:**
```
optimize/retry-imacpro.taila8bdd.ts.net-exp1
optimize/init-imacpro.taila8bdd.ts.net-exp2
optimize/buffer-imacpro.taila8bdd.ts.net-exp3
```

### Workflow Flow

```
┌──────────────────────────────────────────────────────────────┐
│                    AUTO-WORKFLOW FLOW                        │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. CREATE WORKTREE                                          │
│     → git worktree add ../optimize/target-host-expN         │
│                    ↓                                         │
│  2. EXECUTOR MAKES CHANGES                                   │
│     → Changes happen in isolated worktree                    │
│     → NOT on main branch!                                    │
│                    ↓                                         │
│  3. IF IMPROVEMENT                                           │
│     → Commit to optimize branch                              │
│     → Push to origin/optimize/... (NOT main!)                │
│                    ↓                                         │
│  4. HUMAN REVIEW                                             │
│     → Creates PR from optimize → main                       │
│     → Manual merge after review                              │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Branching Rule Definition

```elisp
λ auto-workflow-branching(x).
    change(x) → branch(optimize/{target}-{hostname}-exp{N})
    | push(optimize/...) → origin/optimize/...
    | ¬push(main)
    | human_review → merge(main)
```

### Code Location

The push logic is in `gptel-tools-agent.el:1134`:

```elisp
(when gptel-auto-experiment-auto-push
  (magit-git-success "push" "origin" gptel-auto-workflow--current-branch))
```

### Common Mistake to Avoid

**❌ WRONG:** Pushing changes directly to main branch
```bash
git push origin main  # VIOLATES BRANCHING RULE
```

**✅ CORRECT:** Push to optimize branch, then merge via PR
```bash
git push origin optimize/target-host-exp1
# Then create PR for human review
```

---

## The "Never Ask" Principle

Auto-workflow is fully autonomous. It never interrupts for user input.

### The Core Axiom

```
λ autonomous(x).
    fail(x) → retry(x)
    | retry(x) → retry(x)
    | max_retries → log_and_continue
    | ¬ask(user)
    | ¬stop_for_input
```

### What This Means

Auto-workflow **never** asks the user for:
- Confirmation ("Continue?")
- Input ("What should I do?")
- Decision ("Which approach?")
- Clarification ("Explain more?")

Instead, it always:
1. Tries again automatically
2. Tries a different approach
3. Logs the failure and continues
4. Moves to the next target

### Retry Pattern Implementation

```elisp
(defun gptel-auto-workflow--with-retry (fn max-retries delay)
  "Call FN with automatic retry, never ask user."
  (let ((attempts 0)
        (last-error nil))
    (while (< attempts max-retries)
      (cl-incf attempts)
      (condition-case err
          (return-from gptel-auto-workflow--with-retry
            (funcall fn))
        (error
         (setq last-error err)
         (when (< attempts max-retries)
           (message "Attempt %d/%d failed: %s. Retrying..."
                    attempts max-retries (error-message-string err))
           (sit-for delay))))))
    (message "All %d attempts exhausted. Logging and continuing..."
             max-retries)
    (gptel-auto-workflow--log-failure last-error)
    nil))
```

### Decision Matrix: What To Do On Failure

| Failure Scenario | ❌ Don't Do This | ✅ Do This |
|-------------------|------------------|------------|
| Worktree create fails | Ask user "Retry?" | Retry automatically with backoff |
| Test fails | Ask "Continue?" | Log result, continue to next target |
| LLM timeout | Ask "What now?" | Retry with shorter prompt |
| Push fails | Ask "Force push?" | Retry with fresh auth token |
| Buffer killed | Ask "What buffer?" | Fall back to original buffer |
| No improvement | Ask "Stop?" | Move to next target |

### Functions Never Used in Auto-Workflow

```elisp
;; NEVER use these in auto-workflow code:
y-or-n-p              ; Blocks for user input
yes-or-no-p           ; Blocks for user input  
read-from-minibuffer  ; Blocks for user input
completing-read       ; Blocks for user input
user-error            ; Use only for truly fatal errors
```

---

## Multi-Project Configuration

Auto-workflow can operate on multiple projects using Emacs' built-in `.dir-locals.el` mechanism.

### Project Detection Priority

`gptel-auto-workflow--project-root` checks in this order:

1. **Override variable** (from .dir-locals.el)
   - `gptel-auto-workflow--project-root-override`
2. **Git root** (auto-detected via `git rev-parse --show-toplevel`)
3. **Fallback** - `~/.emacs.d/`

### Configuring via .dir-locals.el

Place this in your project's `.dir-locals.el`:

```elisp
((nil
  . ((gptel-auto-workflow--project-root-override . "/path/to/project")
     (gptel-auto-workflow-targets . ("src/main.el" "src/utils.el"))
     (gptel-auto-experiment-max-per-target . 5)
     (gptel-auto-experiment-time-budget . 1200)
     (gptel-backend . gptel--dashscope)
     (gptel-model . qwen3.5-plus))))
```

### Example: Python Project

```elisp
;; .dir-locals.el for ~/myproject/
((python-mode
  . ((gptel-auto-workflow--project-root-override . "~/myproject")
     (gptel-auto-workflow-targets . ("main.py" "lib/utils.py"))
     (gptel-auto-experiment-max-per-target . 3)
     (gptel-auto-experiment-time-budget . 600))))
```

### Manual Project Switching

```elisp
;; Interactively set project root
M-x gptel-auto-workflow-set-project-root

;; Programmatically
(setq gptel-auto-workflow--project-root-override "/custom/path")
```

---

## Session Architecture

Each experiment runs in its own git worktree with all subagents sharing the same context:

```
┌─────────────────────────────────────────────────────────────┐
│  WORKTREE: optimize/target-host-exp1                        │
│  (default-directory: /path/to/worktree)                     │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐           │
│  │  analyzer   │ │  executor   │ │   grader    │           │
│  │  subagent   │ │  subagent   │ │  subagent   │           │
│  └─────────────┘ └─────────────┘ └─────────────┘           │
│  All subagents share worktree's default-directory           │
└─────────────────────────────────────────────────────────────┘
```

---

## Known Issues and Fixes

### Bug: Deleted Buffer During Execution

**Discovery Date:** 2026-03-25  
**Symptom:** `error "Selecting deleted buffer"` during E2E test

**Root Cause:**  
The advice `gptel-auto-workflow--advice-task-override` overrides `current-buffer` to return a fixed project buffer. If that buffer is killed during async execution, all callbacks fail.

**Timeline:**
- Project buffer `*gptel-agent:.emacs.d*` gets deleted during execution
- Executor runs 560s+ without completing
- No results logged to TSV file

**Fix Applied:**

```elisp
;; 1. Protect buffer from being killed during run
(add-hook 'kill-buffer-query-functions
          #'gptel-auto-workflow--protect-buffer)

;; 2. Check buffer liveness each call, fallback if killed
(defun gptel-auto-workflow--current-buffer-safe ()
  "Get current buffer, checking liveness."
  (if (buffer-live-p gptel-auto-workflow--project-buffer)
      gptel-auto-workflow--project-buffer
    (current-buffer)))  ; Fall back to actual current buffer

;; 3. Save original before overriding
(defvar gptel-auto-workflow--original-current-buffer
  (symbol-function 'current-buffer))
```

**Result:**
- E2E test passed - experiment completed in 230s
- Decision: `kept`
- Score improved: 0.40 → 0.41
- Commit `bae1b73` merged to staging

---

## Configuration Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `gptel-auto-workflow--project-root-override` | `nil` | Override project root path |
| `gptel-auto-workflow-targets` | `("init.el")` | Files to optimize |
| `gptel-auto-experiment-max-per-target` | `10` | Max experiments per target |
| `gptel-auto-experiment-time-budget` | `3600` | Time budget in seconds |
| `gptel-auto-experiment-auto-push` | `t` | Auto-push to remote |
| `gptel-backend` | `gptel--dashscope` | LLM backend to use |
| `gptel-model` | `qwen3.5-plus` | Model name |

---

## Related

- [gptel-tools-agent.el](./gptel-tools-agent.el) - Main implementation
- [git-worktree](./git-worktree) - Branch isolation mechanism
- [gptel-configuration](./gptel-configuration) - LLM backend setup
- [Emacs .dir-locals.el](https://www.gnu.org/software/emacs/manual/html_node/emacs/Directory-Variables.html) - Emacs built-in per-directory settings

---

*Last updated: 2026-03-28*