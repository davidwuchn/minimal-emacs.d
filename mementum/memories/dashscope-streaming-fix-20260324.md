💡 dashscope-streaming-fix

## Problem
DashScope streaming returned 401 Unauthorized, then repeated errors.

## Root Causes
1. **Header nil**: `gptel-make-dashscope` passed `:header nil`, overriding default
2. **Missing host**: Backend definition didn't include `:host`, defaulting to api.openai.com
3. **Old broken method**: Previous custom parser (`cl-return` without `cl-block`) persisted in running Emacs

## Solution
1. Use `(apply #'gptel-make-openai name args)` - delegates all args including default header
2. Add explicit `:host "coding.dashscope.aliyuncs.com"` to backend definition
3. Restart Emacs daemon to clear old broken methods

## Verification
```
emacsclient -e '(gptel-backend-host gptel--dashscope)'
=> "coding.dashscope.aliyuncs.com"

Streaming test: "Say exactly: test ok" => "test ok" ✓
```

## Key Files
- `lisp/modules/gptel-ext-backends.el` - backend definitions
- `packages/gptel/gptel-openai.el` - standard OpenAI parser (handles reasoning_content)