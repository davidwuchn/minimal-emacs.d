---
title: Auto-Workflow System
status: active
category: knowledge
tags: [auto-workflow, gptel, emacs, automation, agent]
---

# Auto-Workflow System

The auto-workflow system enables autonomous AI-driven code improvement in Emacs. It runs unattended, optimizes targets, and never requires human input to proceed.

## Branching Rules

### Branch Format

All auto-workflow experiments use the following branch naming convention:

```
optimize/{target-name}-{hostname}-exp{N}
```

| Component | Description | Example |
|-----------|-------------|---------|
| `optimize/` | Prefix indicating optimization branch | `optimize/` |
| `{target-name}` | Name of file or target being optimized | `retry-imacpro.taila8bdd.ts.net` |
| `{hostname}` | Machine identifier | `exp1` |
| `exp{N}` | Experiment number | `exp1` |

**Full Example:**
```
optimize/retry-imacpro.taila8bdd.ts.net-exp1
```

### Workflow Flow

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Create Branch  │────▶│  Work in Tree   │────▶│  Commit Changes │
│  optimize/...   │     │  (isolated)     │     │  to optimize/   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                         │
                                                         ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Merge via PR   │◀────│  Human Review   │◀────│   Push to Origin│
│  (main branch)  │     │  (gatekeeper)   │     │  optimize/...   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

### The Branching Rule

```elisp
;; gptel-tools-agent.el:1134
(when gptel-auto-experiment-auto-push
  (magit-git-success "push" "origin" gptel-auto-workflow--current-branch))
```

**Key Principles:**
- Changes push to `origin/optimize/...` — NOT `main`
- Each experiment runs in an isolated worktree
- Human review required before merging to main
- Multiple machines can optimize the same target without conflict

### CLI Commands for Branching

```bash
# Create new experiment branch
git worktree add -b optimize/retry-imacpro.taila8bdd.ts.net-exp1 ../worktrees/exp1 ~/.emacs.d

# Push experiment branch
git push origin optimize/retry-imacpro.taila8bdd.ts.net-exp1

# List all experiment branches
git branch -a | grep optimize/
```

## The "Never Ask" Principle

### The Core Rule

Auto-workflow is **fully autonomous**. It never blocks to ask the user for:

- Confirmation
- Input
- Decision
- Clarification

### The Autonomous Lambda

```elisp
λ autonomous(x).
    fail(x) → retry(x)
    | retry(x) → retry(x)
    | max_retries → log_and_continue
    | ¬ask(user)
    | ¬stop_for_input
```

### Retry Pattern Implementation

```elisp
(defun gptel-auto-workflow--with-retry (fn max-retries delay)
  "Call FN with automatic retry on failure, never ask user.
MAX-DELRIES is number of attempts before giving up.
DELAY is seconds to wait between retries."
  (let ((attempts 0)
        (last-error nil))
    (while (< attempts max-retries)
      (cl-incf attempts)
      (condition-case err
          (progn
            (funcall fn)
            (cl-return t))  ; Success - return immediately
        (error
         (setq last-error (cadr err))
         (when (< attempts max-retries)
           (message "[Retry] Attempt %d/%d failed: %s"
                    attempts max-retries last-error)
           (sleep-for delay))))))
    (message "[Auto-Workflow] All %d retries exhausted: %s"
             max-retries last-error)
    nil))
```

### What NOT to Use in Auto-Workflow

| Function | Reason | Alternative |
|----------|--------|-------------|
| `y-or-n-p` | Blocks for input | Retry automatically |
| `yes-or-no-p` | Blocks for input | Log and continue |
| `read-from-minibuffer` | Requires input | Use defaults or config |
| `completing-read` | Requires input | Use predefined list |
| `user-error` (for recoverable) | May stop flow | Use `message` + continue |

### Failure Handling Table

| Failure Type | Don't Do This | Do This |
|--------------|---------------|---------|
| Worktree create fails | Ask user "Retry?" | `gptel-auto-workflow--with-retry` |
| Test fails | Ask "Continue?" | Log failure, move to next target |
| LLM timeout | Ask "What now?" | Retry with shorter prompt |
| Push fails | Ask "Force push?" | Retry with fresh auth token |
| Buffer killed | Ask "Restore?" | Check liveness, recreate buffer |

### Why This Matters

- Auto-workflow runs at 2 AM unattended
- No human is watching to answer questions
- Each failure is an opportunity to retry
- Eventual success > immediate failure

## Multi-Project Configuration

### Using .dir-locals.el

Auto-workflow supports multiple projects via Emacs' built-in `.dir-locals.el` mechanism.

### Project Detection Priority

1. **Override variable** (from .dir-locals.el)
   - Variable: `gptel-auto-workflow--project-root-override`
2. **Git root** (auto-detected)
   - Command: `git rev-parse --show-toplevel`
3. **Fallback**
   - Default: `~/.emacs.d/`

### Configuration Example

Place `.dir-locals.el` in your project root:

```elisp
((nil
  . ((gptel-auto-workflow--project-root-override . "/path/to/project")
     (gptel-auto-workflow-targets . ("src/main.el" "src/utils.el"))
     (gptel-auto-experiment-max-per-target . 5)
     (gptel-auto-experiment-time-budget . 1200)
     (gptel-backend . gptel--dashscope)
     (gptel-model . qwen3.5-plus))))
```

### Manual Project Switching

```elisp
M-x gptel-auto-workflow-set-project-root
```

Or programmatically:

```elisp
(setq gptel-auto-workflow--project-root-override "/my/project")
```

### Session Architecture (Per Worktree)

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

Each experiment worktree has its own `default-directory`, and all subagents within that worktree share the same working directory context.

## Troubleshooting

### E2E Bug: Deleted Buffer Error

**Symptoms:**
- Error message: `Selecting deleted buffer`
- Executor runs 560s+ without completing
- No results logged to TSV file
- Project buffer `*gptel-agent:.emacs.d*` gets deleted during execution

**Root Cause:**
The advice `gptel-auto-workflow--advice-task-override` overrides `current-buffer` to return a fixed project buffer. If that buffer is killed during async execution, all callbacks fail with the deleted buffer error.

**Fix Applied:**

```elisp
;; 1. Protect buffer from being killed during execution
(defun gptel-auto-workflow--protect-buffer (buffer)
  (push buffer kill-buffer-query-functions))

;; 2. Check buffer liveness before each call
(defun gptel-auto-workflow--current-buffer-safe ()
  "Return current buffer, checking for deleted buffers."
  (if (buffer-live-p gptel-auto-workflow--project-buffer)
      gptel-auto-workflow--project-buffer
    (current-buffer)))  ; Fall back to original
```

**Results After Fix:**
- Experiment completed in 230s (down from 560s+)
- Score improved: 0.40 → 0.41
- Commit `bae1b73` merged to staging

### Common Error Patterns

| Error | Likely Cause | Fix |
|-------|--------------|-----|
| `Selecting deleted buffer` | Buffer killed during async | Check `buffer-live-p` before use |
| `Wrong type argument: bufferp, nil` | Buffer not created | Ensure worktree exists first |
| `Git worktree not found` | Worktree path invalid | Check `default-directory` |
| `Remote branch not found` | Didn't push to origin | Verify `git push` succeeded |

### Debugging Commands

```elisp
;; Check current buffer liveness
(buffer-live-p (get-buffer "*gptel-agent:.emacs.d*"))

;; List all worktrees
(magit-git-success "worktree" "list")

;; Check current experiment branch
(gptel-auto-workflow--current-branch)

;; Verify project root detection
(gptel-auto-workflow--project-root)
```

## Anti-Patterns to Avoid

1. **Pushing directly to main** — Always use optimize branch flow
2. **Blocking for user input** — Use retry logic instead
3. **Hardcoding project paths** — Use `.dir-locals.el` for multi-project
4. **Assuming buffer exists** — Check `buffer-live-p` before use
5. **No fallback on failure** — Always log and continue

## Related

- [gptel-agent Configuration](/gptel-agent-config)
- [Worktree Management](/git-worktree)
- [Emacs Directory Variables](/dir-locals)
- [Magit Branching](/magit-branching)
- [Subagent Architecture](/subagents)
- [TSV Logging](/tsv-logging)

---

*This knowledge page covers the core auto-workflow system. For advanced topics, see the advanced automation patterns document.*