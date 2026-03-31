# Sanitize Log Messages for Multi-line Content

**Symbol:** 🔁 pattern  
**Date:** 2026-03-31

## Problem

Messages buffer showed `*ERROR*: Unknown message: X` errors during auto-workflow execution. The errors appeared when logging multi-line strings (agent output, review results, etc.) - Emacs split the message at `\n` characters, causing fragmented output.

## Solution

Added `my/gptel--sanitize-for-logging` helper function that escapes `\n`, `\r`, and `\t` before logging:

```elisp
(defun my/gptel--sanitize-for-logging (text &optional max-len)
  "Sanitize TEXT for safe logging to Messages buffer.
Replaces newlines and control chars with escaped representations."
  (if (not (stringp text))
      "nil"
    (let ((result (replace-regexp-in-string
                   "[\n\r\t]" 
                   (lambda (m) (pcase m ("\n" "\\n") ("\r" "\\r") ("\t" "\\t")))
                   text t t)))
      (if max-len
          (truncate-string-to-width result max-len nil nil "...")
        result))))
```

## Applied To

- Agent output logging (first 500 chars, preview 200 chars)
- Review result logging
- Fix output logging
- Validation error logging
- Error snippet logging

## Impact

Cosmetic fix only - workflow functioned correctly before. Now log output is cleaner and easier to read.

## Related

- `gptel-tools-agent.el:638-656` (helper function)
- `gptel-tools-agent.el:2283,2298` (agent output)
- `gptel-tools-agent.el:1334` (review output)
- `gptel-tools-agent.el:1559,1575` (fix/review output)
- `gptel-tools-agent.el:2350` (validation error)
- `gptel-tools-agent.el:2163,2167` (error snippets)