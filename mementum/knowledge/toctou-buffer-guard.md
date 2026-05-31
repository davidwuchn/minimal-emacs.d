---
title: TOCTOU Buffer Guard Pattern
status: active
category: patterns
tags: [emacs-lisp, concurrency, buffers, async, defensive-programming]
related: [buffer-management, async-workflows, error-recovery]
---

# TOCTOU Buffer Guard Pattern

## Problem

Time-of-Check-Time-of-Use (TOCTOU) race conditions occur in Emacs Lisp when
a buffer is checked for existence at one point but by the time the code acts
on it, the buffer has been killed. This is especially common in async
workflows where a lambda closure captures a buffer reference:

```elisp
;; TOCTOU vulnerable pattern:
(dolist (buf (buffer-list))
  (when (buffer-live-p buf)          ;; check passes here
    (run-with-timer
     0.1 nil
     (lambda ()
       (with-current-buffer buf      ;; used later — buf may be dead
         (do-something))))))
```

## Solution

Use defense-in-depth at the use site with three protective layers:

```elisp
(lambda ()
  (when (and buf (buffer-live-p buf))
    (ignore-errors
      (with-current-buffer buf
        (do-something)))))
```

### Layer 1: Existence + liveness check
`(when (and buf (buffer-live-p buf))` — check buffer is non-nil AND alive
at use time, not at capture time.

### Layer 2: `ignore-errors`
Wraps the buffer operation so that if the buffer is killed between the
liveness check and the actual use (narrow race window), the error is caught
rather than propagating.

### Layer 3: `with-current-buffer` (not `set-buffer`)
`with-current-buffer` restores the original buffer on exit, preventing
side effects on the rest of the codebase.

## Real-World Example

Found in `gptel-auto-workflow-projects.el` where async subagent callbacks
iterate over project buffers:

```elisp
(defun gptel-auto-workflow-list-project-buffers (&optional where)
  (let ((buffers (gptel-auto-workflow--normalized-projects)))
    (dolist (buf buffers)
      (when (buffer-live-p buf)
        ;; async operation captures buf in closure
        (gptel-auto-workflow--run-async
         (lambda (result)
           (when (and buf (buffer-live-p buf))        ;; TOCTOU guard
             (with-current-buffer buf
               (process-result result))))))))))
```

## Variations

| Context | Guard Pattern |
|---------|--------------|
| Timer callback | `(when (buffer-live-p buf) (with-current-buffer buf ...))` |
| Process sentinel | `(when (and buf (buffer-live-p buf)) (ignore-errors ...))` |
| Async subagent | `(when-let ((buf (get-buffer name))) (with-current-buffer buf ...))` |
| Batch processing | Wrap loop body in `ignore-errors` |
