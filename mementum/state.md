# Mementum State

> Last session: 2026-03-24

## Built ✓

**DashScope Streaming Fixed**

| Before | After |
|--------|-------|
| `:stream nil` (workaround) | `:stream t` (fixed) |
| HTTP parsing errors | Robust SSE parser |
| lite-executor only | Full executor viable |

### Technical Details

```elisp
(cl-defstruct (gptel-dashscope (:include gptel-openai)))
(cl-defmethod gptel-curl--parse-stream ((_backend gptel-dashscope) info)
  ;; Custom parser handles DashScope's SSE format differences
  )
```

### A/B Test

Run in Emacs (not emacsclient due to async limitations):

```elisp
(gptel-ab-test-run "Simple prompt")
```

Compares:
- :lite-executor (4 tools, no stream)
- :executor (27 tools, streaming)

### Session Commits

| Commit | Description |
|--------|-------------|
| `6fb1a0d` | ⚡ fix DashScope streaming: custom SSE parser |
| `59bcd6e` | 💡 dashscope-streaming-fix: custom SSE parser pattern |
| `f9d19a7` | ◈ state: A/B test framework |
| `1d2ebaa` | Δ fix A/B test |
| `4d7676a` | ⚡ add A/B test framework |
| `1f5583a` | Δ fix quality scoring |
| `5ff621d` | Δ fix code quality issues |

## Pattern Discovered 🔁

**Git History → Workarounds → Proper Fixes**

```
git log --grep="workaround\|fix\|bypass"
  → identify root cause
  → implement proper fix
  → A/B test to compare
  → remove workaround
```

## Next Steps

1. Run A/B test in Emacs to compare lite-executor vs executor
2. If streaming is reliable, remove lite-executor fallback
3. Consider fixing other backends with similar issues