# Buffer Iteration Refactoring Opportunity

## Pattern Detected
Two functions use identical defense-in-depth buffer iteration:
- `gptel-auto-workflow-clear-executor-overlays`
- `gptel-auto-workflow-list-project-buffers`

Both repeat the pattern:
```elisp
(gptel-auto-workflow--iterate-project-buffers
  (lambda (root buf)
    (when (and buf (buffer-live-p buf))
      (ignore-errors ...))))
```

## Hypothesis
Extracting `gptel-auto-workflow--with-live-buffer` macro would:
- Reduce code duplication (φ Vitality)
- Make defense-in-depth explicit (Clarity)
- Enable easier testing (∀ Vigilance)

## Experiment Type
**Refactoring** - Extract common macro

## Code Evidence
- Lines 780-793: clear-executor-overlays iteration
- Lines 802-815: list-project-buffers iteration
- Both use identical buffer-live-p + ignore-errors pattern
