# Buffer-Local Variable Pattern

**Date**: 2026-04-02
**Category**: pattern
**Related**: auto-workflow, fsm, buffers

## Pattern

Buffer-local variables must be set in the correct buffer context.

## Problem

```elisp
;; WRONG - sets in current buffer, not target
(setq gptel--fsm-last fsm)

;; WRONG - not buffer-local
(setq-local gptel--fsm-last fsm)  ; in wrong buffer
```

## Solution

```elisp
;; RIGHT - switch to target buffer first
(with-current-buffer target-buf
  (setq-local gptel--fsm-last fsm))

;; Or create in current buffer if that's correct context
(setq-local gptel--fsm-last fsm)  ; in correct buffer
```

## Common Buffer-Local Variables

- `gptel--fsm-last` - FSM state
- `gptel-backend` - LLM backend
- `gptel-model` - Model name
- `gptel--stream-buffer` - Response buffer

## Signal

- Variable is nil unexpectedly → check buffer context
- Variable works in some buffers but not others → buffer-local issue
- Use `with-current-buffer` to ensure correct context

## Test

```elisp
(with-current-buffer target
  (should gptel--fsm-last))  ; Verify set in correct buffer
```