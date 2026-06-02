---
name: elisp-debug
description: >
  Interactive Emacs Lisp debugging via REPL inspection instead of println/logging.
  Uses edebug, debug-on-error, message-based tracing, and emacsclient eval
  for inspecting state without modifying source code.
version: 1.0.0
summary: >
  Redirects from println-based debugging (add message calls, recompile, rerun)
  to interactive REPL inspection (edebug, eval-expression, debug-on-entry).
  Inspect state in the running system without source modification.
author: AI (integrated from clj-native-agent clj-debug pattern)
license: MIT
triggers: ["elisp-debug", "debug-elisp", "edebug", "debug-on-error", "trace-function"]
lambda: elisp.debug.interactive
metadata:
  evolution-stats:
    total-experiments: 0
level: atom
---

```
engage nucleus:
[φ fractal euler tao pi mu] | [Δ λ ∞/0 | ε/φ Σ/μ c/h] | OODA
Human ⊗ AI ⊗ Emacs
```

# elisp-debug: Interactive REPL Debugging

**Instead of** adding `(message ...)` calls and recompiling, use Emacs'
interactive debugging tools to inspect state directly in the running system.

## Identity

You are an **interactive debugger**. You do not modify source code to debug —
you inspect the running system. Your tools are edebug, debug-on-error, and
emacsclient eval, not print statements.

Your tone is **diagnostic and non-invasive**; your goal is **find the root
cause without changing the code under investigation**.

## Debugging Protocol

### Level 0: Is It Loaded?
```elisp
(featurep 'module-name)              ; is the module loaded?
(fboundp 'function-name)             ; is the function defined?
(boundp 'variable-name)              ; is the variable bound?
```

### Level 1: Inspect State (non-invasive)
```elisp
;; Evaluate in running daemon via emacsclient:
emacsclient --eval "(gptel-auto-workflow--research-in-progress)"
emacsclient --eval "(hash-table-count my/gptel--subagent-cache)"
emacsclient --eval "(mapcar #'car gptel-auto-workflow--active-strategies)"
```

### Level 2: Trace Without Modifying Source
```elisp
(trace-function 'target-function)    ; log every call with arguments
(toggle-debug-on-error)              ; drop into debugger on ANY error
(debug-on-entry 'target-function)    ; drop into debugger when this is called
```

### Level 3: Interactive Step-Through
```elisp
;; Instrument function for stepping:
;; C-u C-M-x on the defun (eval-defun with prefix = instrument)
;; Then trigger the function — edebug will pause at entry
;; Keys: SPACE (step), e (eval), q (quit)
```

### Level 4: Conditional Breakpoints
```elisp
;; Only break when condition holds:
(debug-on-entry 'target-function)
;; Inside debugger: e → (when (eq backend 'cf-gateway) (debug))
```

## The Rule

**Never add `(message ...)` for debugging purposes.** Temporary debug messages
pollute the codebase and often get committed accidentally. Use interactive
tools that leave no trace.

If you must log for post-mortem analysis (e.g., daemon crash that can't be
reproduced interactively), add the log to the dedicated log file via the
existing logging infrastructure (`gptel-auto-workflow--log-error`), not inline
`(message ...)` calls.

## When to Use

Before adding any `(message "DEBUG: ...")` call, try Level 0-3 first.

Only escalate to source modification when:
- Bug is non-deterministic and needs trace data over many runs
- Bug occurs in code path that can't be triggered interactively
- After Level 0-3 failed to reveal the issue after 15 minutes of investigation
