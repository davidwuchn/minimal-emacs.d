# A/B Testing Framework for Executors

## Purpose

Compare executor variants to make data-driven decisions about tool selection and streaming.

## Usage

```elisp
;; Run in Emacs (not emacsclient - async doesn't work via client)
(gptel-ab-test-run "Your test prompt")
```

## Variants

| Variant | Tools | Stream | Use Case |
|---------|-------|--------|----------|
| lite-executor | 4 | No | Fast, simple tasks |
| executor | 27 | Yes | Complex, multi-step tasks |

## Results Format

```
| Variant | Success | Duration | Output Len | Error |
|---------|---------|----------|------------|-------|
| :lite-executor | ✓ | 5.2s | 150 | - |
| :executor | ✓ | 4.8s | 150 | - |
```

## Decision Criteria

1. **Reliability** - Both must succeed
2. **Speed** - Faster is better
3. **Capability** - More tools = more complex tasks possible
4. **UX** - Streaming provides incremental output

## When to Use Which

| Situation | Recommendation |
|-----------|----------------|
| Simple edit | lite-executor |
| Complex refactoring | executor |
| Multi-file changes | executor |
| Quick question | lite-executor |
| Tool-heavy tasks | executor |

## Implementation

```elisp
(defvar gptel-ab-test--variants
  '((:lite-executor :agent-type "lite-executor" ...)
    (:executor :agent-type "executor" ...)))

(defun gptel-ab-test-run (prompt &optional callback)
  ;; Run each variant, measure success/duration
  ;; Display results in *A/B Test Results* buffer
  )
```

## Integration with Auto-Evolution

After DashScope streaming fix, can now use full executor for experiments:

```elisp
(setq gptel-auto-experiment-use-lite nil)  ; Use full executor
```

---
*Created: 2026-03-24*