---
title: Emacs Development Patterns
status: active
category: knowledge
tags: [emacs, elisp, patterns, anti-patterns, debugging, workflow]
---

# Emacs Development Patterns

This knowledge page captures recurring patterns, anti-patterns, and best practices discovered through development of Emacs packages, particularly around the gptel ecosystem.

## Table of Contents

1. [Buffer-Local Variable Pattern](#buffer-local-variable-pattern)
2. [Nil Guard Pattern](#nil-guard-pattern)
3. [Module Load Order Pattern](#module-load-order-pattern)
4. [FSM Creation Pattern](#fsm-creation-pattern)
5. [Nested Defun Anti-Pattern](#nested-defun-anti-pattern)
6. [Cron-Based Scheduling](#cron-based-scheduling)
7. [Upstream Cooperation Pattern](#upstream-cooperation-pattern)
8. [LLM-Generated Syntax Error Anti-Pattern](#llm-generated-syntax-error-anti-pattern)
9. [Worktree Cleanup Pattern](#worktree-cleanup-pattern)
10. [Quick Reference](#quick-reference)

---

## Buffer-Local Variable Pattern

**Problem**: Buffer-local variables must be set in the correct buffer context. Accessing them from the wrong buffer returns nil unexpectedly.

### Incorrect Approaches

```elisp
;; WRONG - sets in current buffer, not target
(setq gptel--fsm-last fsm)

;; WRONG - not buffer-local when in wrong buffer
(setq-local gptel--fsm-last fsm)  ; executes in wrong buffer context
```

### Correct Solution

```elisp
;; RIGHT - switch to target buffer first
(with-current-buffer target-buf
  (setq-local gptel--fsm-last fsm))

;; Or create in current buffer if that's the correct context
(setq-local gptel--fsm-last fsm)  ; when current buffer IS the target
```

### Common Buffer-Local Variables in gptel

| Variable | Purpose | File Defined |
|----------|---------|--------------|
| `gptel--fsm-last` | FSM state for request handling | `gptel-request.el` |
| `gptel-backend` | LLM backend selection | `gptel.el` |
| `gptel-model` | Model name/identifier | `gptel.el` |
| `gptel--stream-buffer` | Response streaming buffer | `gptel.el` |

### Debugging Signal

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Variable is nil unexpectedly | Wrong buffer context | Use `with-current-buffer` |
| Works in some buffers, not others | Buffer-local not set | Set in correct buffer |
| FSM-related errors in new buffers | FSM not created | Create FSM during buffer setup |

### Verification

```elisp
(with-current-buffer target
  (should gptel--fsm-last))  ; Verify set in correct buffer
```

**Related**: [FSM Creation Pattern](#fsm-creation-pattern)

---

## Nil Guard Pattern

**Problem**: Elisp functions like `=`, `make-overlay`, `copy-marker` throw `wrong-type-argument` when passed nil. This crashes in process sentinels and FSM callbacks.

### Guard Patterns

```elisp
;; Guard before arithmetic comparison
(and (numberp status) (= status 400))

;; Guard before overlay creation
(and (markerp tm) (marker-position tm) tm)

;; Fallback chain for markers
(or (and (markerp tm) (marker-position tm) tm)
    (with-current-buffer buf (point-marker)))
```

### Real-World Fixes

| File | Lines | Pattern Used |
|------|-------|--------------|
| `gptel-tools-agent.el` | 133-137 | Marker fallback chain |
| `gptel-agent-loop.el` | 506-512 | Marker fallback chain |
| `gptel-ext-tool-confirm.el` | 337-340 | Tool confirm guard |
| `gptel-ext-retry.el` | 314-318 | `(numberp status)` guard |

### Decision Tree

```
λ guard(x).
    nil(x) → fallback(x)
    | marker(x) ∧ valid_position(x) → use(x)
    | marker(x) ∧ ¬valid_position(x) → create_marker(x)
    | number(x) → safe_compare(x)
    | otherwise → handle_error(x)
```

**Related**: [Buffer-Local Variable Pattern](#buffer-local-variable-pattern)

---

## Module Load Order Pattern

**Problem**: `Symbol's value as variable is void` errors when using functions before their dependencies are loaded.

### Incorrect Approach

```elisp
;; ERROR: gptel--tool-preview-alist is void
(gptel
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-RSv7PT.txt. Use Read tool if you need more]...