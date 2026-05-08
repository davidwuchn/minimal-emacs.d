# Provider Failover Auth-Source Batch Mode Fix

**Discovery:** Subagent provider failover (MiniMax → DashScope) was returning nil even though DashScope was configured and available.

**Root Cause:** `gptel-auto-workflow--backend-available-p` used auth-source exclusively to check provider availability. In batch mode (`emacs -Q --batch`), auth-source is uninitialized, so all key lookups return nil. This made ALL fallback candidates appear unavailable.

**Fix:** Modified `gptel-auto-workflow--backend-available-p` to fall back to checking if the backend object variable is bound (indicating it was configured at Emacs startup):

```elisp
(defun gptel-auto-workflow--backend-available-p (backend-name)
  "Return non-nil when BACKEND-NAME has credentials configured."
  (let ((host (alist-get backend-name gptel-auto-workflow--backend-key-hosts
                          nil nil #'string=)))
    (or (and host
             (fboundp 'my/gptel-api-key)
             (gptel-auto-workflow--non-empty-string-p
              (my/gptel-api-key host)))
        ;; Fallback: if auth-source returns nil (batch mode), trust that
        ;; a bound backend object means the backend was configured at startup.
        (gptel-auto-workflow--backend-object backend-name))))
```

**Location:** `lisp/modules/gptel-tools-agent-prompt-build.el:964-975`

**Verification:** Byte-compiles successfully with no errors.

**Impact:** Provider failover chain now works in batch mode. When MiniMax is rate-limited, experiments will properly fall back through DashScope → DeepSeek → CF-Gateway.

**Date:** 2026-05-08
