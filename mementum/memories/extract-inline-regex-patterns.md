# Extract inline regex patterns into named defconst

When a function contains inline regex patterns that define behavioral boundaries (task detection, keyword matching, etc.), extract them into a named `defconst` alist mapping symbols to patterns.

## Benefits
- **Fractal Clarity**: Makes assumptions explicit and independently verifiable
- **φ Vitality**: Enables pattern adaptation without touching function logic
- **Testability**: Patterns can be inspected and tested independently
- **Reduced duplication**: Single source of truth for pattern definitions

## Implementation pattern
```elisp
(defconst my--patterns
  '((type-a . "regex\\|pattern")
    (type-b . "other\\|regex"))
  "Maps type symbols to regex patterns.
Used by `my-detect-function'.")

(defun my-detect-function (input)
  (or (car (cl-find-if (lambda (p) (string-match-p (cdr p) input))
                       my--patterns))
      'default))
```

## Anti-pattern
- Don't extract if the regex is used only once and is simple (< 3 alternatives)
- Don't extract if patterns need dynamic construction