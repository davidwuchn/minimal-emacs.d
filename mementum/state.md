# Mementum State

> Last session: 2026-03-24

## Built ✓

**DashScope Streaming: WORKING!**

| Before | After |
|--------|-------|
| `:stream nil` workaround | `:stream t` working |
| HTTP parsing errors | Robust SSE parser |
| lite-executor only | Full executor viable |

### Root Cause

1. **URL was nil** - struct constructor didn't set it
2. **Model format** - needed plain symbols not plist specs
3. **Stream parser** - DashScope SSE differs from OpenAI

### Fix Chain

```
6fb1a0d → Custom gptel-dashscope struct
54f5c37 → Fixed parser regex issue
8591cfe → Fixed model format
d60312c → Fixed URL nil issue ← STREAMING WORKS
```

### Test

```elisp
(gptel-request "Say: test" :stream t :callback #'message)
;; => "test"
```

### Session Summary

| Commits | Description |
|---------|-------------|
| 9 | DashScope streaming fix |
| 6 | Code quality fixes |
| 2 | A/B test framework |
| 2 | Learning/mementum |

### Pattern: Git History → Fixes

```
commit 630fbd4: "fix DashScope: disable streaming"
    ↓
identify root cause: SSE format differs
    ↓
commit d60312c: "DashScope streaming: WORKING!"
    ↓
A/B test: lite-executor vs executor
```

## Next Steps

1. Run A/B test comparing executors
2. If streaming is reliable, remove lite-executor fallback
3. Document the fix in mementum/knowledge/