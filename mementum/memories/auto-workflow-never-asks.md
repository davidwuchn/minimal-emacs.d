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