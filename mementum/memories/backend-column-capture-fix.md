# Backend Column Must Capture Effective Subagent Backend

## Problem
TSV `backend` column showed global `gptel-backend` (e.g., "MiniMax") even when subagent used a fallback provider (e.g., "CF-Gateway").

This made it impossible to track which backend actually served each experiment.

## Root Cause
```elisp
;; OLD: Captured global backend
(setq experiment-backend
  (gptel-backend-name gptel-backend))
```

Subagents use `gptel-auto-workflow--maybe-override-subagent-provider` which may select a different fallback backend than the global one.

## Solution
Capture the effective backend by checking override preset first:
```elisp
;; NEW: Captures effective backend including overrides
(setq experiment-backend
  (let* ((executor-preset (gptel-auto-workflow--get-active-agent-preset "executor"))
         (override-preset (gptel-auto-workflow--maybe-override-subagent-provider "executor" executor-preset)))
    (or (and override-preset (gptel-auto-workflow--preset-backend-name (plist-get override-preset :backend)))
        (gptel-backend-name gptel-backend)
        "unknown")))
```

## Files
- `lisp/modules/gptel-tools-agent-experiment-core.el:823-842`

## Tags
backend, tsv, subagent, provider-override, experiment-logging