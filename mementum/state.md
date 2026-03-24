# Mementum State

> Last session: 2026-03-24

## Built ✓

**DashScope Streaming Fix - In Progress**

| Component | Status |
|-----------|--------|
| Custom backend struct | ✓ gptel-dashscope |
| Custom stream parser | ✓ Implemented |
| Model format fix | ✓ Plain symbols |
| Full streaming test | ⚠ Debugging |

### Issue Discovered

`gptel--sanitize-model` uses `member` to check model availability. When models are stored as `(symbol :capabilities ...)` lists, the check fails and sets `gptel-model` to the entire list instead of the symbol.

**Fix**: Use plain symbol list: `'(qwen3.5-plus ...)` instead of `'((qwen3.5-plus :capabilities ...))`

### Current Error

```
gptel: converting non-string :content on user message
Wrong type argument: stringp, nil
```

May be related to message formatting in gptel.

### Commits

| Commit | Description |
|--------|-------------|
| `8591cfe` | Δ fix DashScope models: plain symbols |
| `54f5c37` | Δ fix stream parser: skip-chars-forward |
| `6fb1a0d` | ⚡ fix DashScope streaming: custom SSE parser |
| `59bcd6e` | 💡 dashscope-streaming-fix pattern |

### Next Steps

1. Debug the "stringp, nil" error in gptel-request
2. Complete streaming test
3. Run A/B test comparing executors

## Pattern: API Compatibility

When extending gptel backends:

1. Use `cl-defstruct` with `:include gptel-openai`
2. Models must be plain symbols or `(symbol :props...)` in backend
3. Custom stream parser via `cl-defmethod gptel-curl--parse-stream`
4. Test with `gptel-request` in Emacs (not emacsclient)