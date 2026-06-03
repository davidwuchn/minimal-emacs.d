When wrapping shell commands or file operations (byte-compile, git commands) in `condition-case`, prefer catching `error` broadly. The pattern:

```elisp
(condition-case err
    (let* (...)
      ...)
  (error
   (format "Operation failed: %s" (error-message-string err))))
```

This prevents unhandled errors from the shell command (e.g., `gptel-auto-workflow--git-result` returning unexpected values, missing files, or shell failures) from propagating up. The pattern was applied to the byte-compile section in `gptel-auto-experiment--build-grading-output` in `gptel-tools-agent-benchmark.el`.