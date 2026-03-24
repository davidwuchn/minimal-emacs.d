# DashScope Backend Configuration

## Streaming Fix

DashScope's SSE format differs from OpenAI's standard, requiring a custom backend.

### Implementation

```elisp
;; 1. Define custom struct extending gptel-openai
(cl-defstruct (gptel-dashscope (:include gptel-openai))
  ;; Inherits all gptel-openai slots
  )

;; 2. Override stream parser
(cl-defmethod gptel-curl--parse-stream ((_backend gptel-dashscope) info)
  ;; Custom parser for DashScope SSE format
  ...)

;; 3. Factory function sets URL correctly
(cl-defun gptel-make-dashscope (name &rest args)
  (let ((backend (gptel--make-dashscope ...)))
    (setf (gptel-backend-url backend) 
          (concat protocol "://" host endpoint))
    backend))
```

### Key Issues Fixed

| Issue | Cause | Fix |
|-------|-------|-----|
| HTTP parsing errors | SSE format differs | Custom parser |
| URL was nil | Constructor didn't set it | setf after creation |
| Model format | plist specs instead of symbols | Plain symbol list |
| Protocol nil | Missing parameter | Default "https" |

### Model Format

```elisp
;; Correct - plain symbols
:models '(qwen3.5-plus qwen3-max qwen3-coder)

;; Incorrect - plist specs break gptel--sanitize-model
:models '((qwen3.5-plus :capabilities (media)) ...)
```

### Stream Parser Differences

| OpenAI | DashScope |
|--------|-----------|
| `data: {"choices":[...]}` | Same format but different line handling |
| Strict regex | More lenient whitespace handling needed |
| `forward-sexp` reliable | Need `skip-chars-forward` |

### Testing

```elisp
(let ((gptel-backend gptel--dashscope)
      (gptel-model 'qwen3.5-plus))
  (gptel-request "test" :stream t :callback #'message))
;; Should return response with streaming
```

---
*Created: 2026-03-24*