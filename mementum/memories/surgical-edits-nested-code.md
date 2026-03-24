# Surgical Edits for Nested Code

## Problem

Large edit operations on deeply nested code (like the experiment workflow with 10+ levels of nesting) can easily break parentheses balance.

## Failed Approach

Replacing a large block with a new block:
```elisp
;; This often breaks due to missing/mismatched parens
(edit old-block new-block)
```

## Successful Approach

1. Make minimal edits - only change what needs changing
2. Edit the beginning first, then the end
3. Verify after each edit

```elisp
;; Step 1: Edit just the function call
(edit "gptel-auto-experiment-decide"
      "(let ((code-quality ...))
         (gptel-auto-experiment-decide")

;; Step 2: Edit just the closing parens
(edit "exp-result))))))))))))"
      "exp-result)))))))))))))")  ; one more paren for let
```

## Verification

```bash
# Check file loads
emacs --batch -l file.el

# Check parentheses balance (may hang if balanced)
timeout 10 emacs --batch --eval "(progn (find-file ...) (while t (forward-sexp)))"
```

## Symbol

λ surgical - minimal changes preserve structure