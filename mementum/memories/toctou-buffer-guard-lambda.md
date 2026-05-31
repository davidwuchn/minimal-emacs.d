When iterating over buffers in async Emacs workflows, add a secondary `buffer-live-p` guard AND nil check at the lambda use site, not just in the iterator. Buffers can be killed between the iterator's check and the lambda execution (TOCTOU race). Pattern:

```elisp
(lambda (root buf)
  (when (and buf (buffer-live-p buf))
    (let ((mode (ignore-errors
                  (with-current-buffer buf
                    (format-mode-line mode-name)))))
      ...)))
```

This provides defense-in-depth: nil guard + liveness check + error wrapping around fragile operations.