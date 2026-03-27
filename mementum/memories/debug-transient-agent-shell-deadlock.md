---
φ: 0.85
e: debug-display-deadlock
e: transient-agent-shell-conflict
λ: (and (eq major-mode 'agent-shell-mode) (called-from-transient-p))
Δ: 0.08
source: session
evidence: 1
context: agent-shell, transient, mode-line, deadlock
---

# Debug Learning: Transient + Agent-Shell Deadlock

## Problem
When starting agent-shell via `C-c a a` (transient menu), Emacs deadlocks during "Initializing..." phase. Works fine with `M-x agent-shell`.

## Root Cause
`force-mode-line-update` conflicts with transient's display system when called during agent-shell buffer initialization. The hook runs while transient still controls window/buffer management.

## Solution Pattern
Use event-based initialization instead of synchronous hooks:

```elisp
;; BAD: Causes deadlock
(add-hook 'agent-shell-mode-hook #'ai-code-behaviors-mode-line-enable)

;; GOOD: Waits for shell to be ready
(add-hook 'agent-shell-mode-hook
          (lambda ()
            (agent-shell-subscribe-to
             :shell-buffer (current-buffer)
             :event 'prompt-ready  ; Shell is ready for input
             :on-event (lambda (_)
                         (ai-code-behaviors-mode-line-enable)))))
```

## Key Insight
Different execution contexts have different display constraints:
- `M-x`: Normal Emacs state - mode-line updates work
- `C-c a a`: Transient active - display system locked until transient exits
- Solution: Defer display operations until after initialization completes

## Debugging Technique
1. Binary search: Disable features one by one to isolate culprit
2. Compare paths: `M-x` vs `C-c a a` behavior differences
3. Event-driven: Look for lifecycle events (prompt-ready, init-finished)
4. Minimize reproducer: Start with minimal decorator, add features incrementally

## Prevention
- Always test both `M-x` and transient paths for display-heavy operations
- Use lifecycle events rather than immediate hooks for display updates
- Document display system dependencies in comments

## Related Patterns
- agent-shell-event-subscription
- transient-display-conflict
- deferred-mode-line-enable

## Evidence
- Fixed deadlock in ai-code-behaviors.el
- Mode-line now auto-enables after prompt-ready event
- All features work: @ completion, # completion, decorator, mode-line
