---
title: Timer-Based Retry Over Direct Recursion
date: 2026-05-16
symbol: 🔁
---

# Timer-Based Retry Over Direct Recursion

Direct recursive retry in async callbacks accumulates stack frames because
each callback fires with the previous call still on the stack. Converting
to `run-with-timer 0` resets the stack each time.

**Anti-pattern** (stack-deepening):
```elisp
(lambda (result)
  (if (retryable result)
      (my-retry-fn callback (1+ attempt))  ;; DIRECT recursion
    (funcall callback result)))
```

**Pattern** (stack-safe):
```elisp
(lambda (result)
  (if (retryable result)
      (let ((cb callback) (att (1+ attempt)))
        (run-with-timer 0 nil              ;; TIMER resets stack
                        (lambda ()
                          (my-retry-fn cb att))))
    (funcall callback result)))
```

Applied at 4 sites across 3 files. Each site was bounded by a retry counter
(2-3 max) so overflow was unlikely, but the pattern eliminates the risk entirely
and reduces pressure on max-lisp-eval-depth (currently 5000).
