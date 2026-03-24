# DashScope Streaming Fix

## Problem
DashScope's SSE format differed from OpenAI's standard, causing:
- HTTP parsing errors mid-stream
- Connection timeouts
- Retry loops that never completed

## Root Cause
The `gptel-curl--parse-stream` regex in gptel-openai.el failed on DashScope's subtle SSE format differences.

## Solution
```elisp
(cl-defstruct (gptel-dashscope (:include gptel-openai)))

(cl-defmethod gptel-curl--parse-stream ((_backend gptel-dashscope) info)
  ;; Robust parser with lenient whitespace handling
  ;; Supports both 'data:' prefixed and raw JSON lines
  ...)
```

## Impact
| Before | After |
|--------|-------|
| `:stream nil` (workaround) | `:stream t` (fixed) |
| lite-executor (4 tools) | executor (27 tools) viable |
| Batch output | Incremental streaming |

## Pattern
When API streaming fails:
1. Check if SSE format differs from expected
2. Create custom backend extending standard one
3. Override `gptel-curl--parse-stream` method
4. Test with `gptel-request`
5. A/B compare performance

## Git History Insight
Commit `630fbd4` documented the workaround but not the fix. This session turned that workaround into a proper solution.

---
*Learned: 2026-03-24*