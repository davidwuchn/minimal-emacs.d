When adding `load-file` in a cron/weekly job context, ALWAYS wrap in `condition-case` because:
1. The file might not exist (module not yet loaded)
2. The file might have load errors (missing dependencies)
3. An uncaught error aborts the entire weekly job batch

Pattern:
```elisp
(condition-case err
    (load-file (expand-file-name file-path root))
  (error
   (message "[%s] Failed to load %s: %s" prefix file-path (error-message-string err))
   nil))
```

This is especially important when `load-file` is outside the main `condition-case`/`unwind-protect` body.