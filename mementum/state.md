# Mementum State

> Last session: 2026-03-24

## Session: DashScope Streaming Fixed ✓

**Problem**: DashScope streaming returned 401 Unauthorized, then `cl-block-nil` errors.

### Root Causes Found

| Issue | Cause | Fix |
|-------|-------|-----|
| 401 Unauthorized | `:header nil` override | Use `apply` to delegate all args |
| Wrong host | Missing `:host` param | Add explicit host |
| cl-block-nil errors | Old broken custom parser | Remove custom parser, use standard |
| nil tool names | DashScope sends malformed calls | Merged fix-nil-tool-names |

### Changes Made

| File | Change |
|------|--------|
| `lisp/modules/gptel-ext-backends.el` | Simplified to `apply #'gptel-make-openai`, added `:host` |
| `packages/gptel/` | Merged `fix-nil-tool-names` branch |

### Verification

```elisp
(gptel-backend-host gptel--dashscope) => "coding.dashscope.aliyuncs.com"
(gptel-backend-header gptel--dashscope) => #[...]  ; has header function

;; Streaming test
(gptel-request "Say exactly: test ok" :stream t) => "test ok" ✓
```

### Key Learnings

1. **No custom parser needed** - DashScope uses standard OpenAI SSE format
2. **DashScope has reasoning_content** - qwen3.5-plus sends thinking blocks
3. **Emacs caches methods** - Must restart daemon after changing generic methods
4. **apply for delegation** - `(apply #'gptel-make-openai name args)` preserves defaults

### Previous Session

**24 commits** | **Streaming fixed** | **Git submodules migrated**