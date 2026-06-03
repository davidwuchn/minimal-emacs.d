# nil-guard pattern for stringp before string-match-p

Functions taking an `output` string parameter can crash if called with nil or non-string input (number, list). Always add `(when (stringp output) ...)` or `(unless (stringp output) (cl-return-from <fn> nil))` at the top of functions that call `string-match-p`, `string-search`, or other string-specific operations.

Example:
```elisp
(defun my-function (output)
  (when (stringp output)
    (let (...) ...)))
```

Note: When using `cl-return-from`, wrap the function body in an explicit `(cl-block <fn-name> ...)` — plain `defun` does not create a block.
