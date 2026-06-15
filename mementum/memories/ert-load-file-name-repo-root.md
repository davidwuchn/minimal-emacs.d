# ERT Repo Root Must Be Captured at Load Time

**Date**: 2026-06-15
**Category**: pattern
**Related**: ert, load-file-name, default-directory, test-fixtures

## Insight

In batch-loaded ERT files, `load-file-name` is only reliable while the file is being loaded. If you compute repo root inside the test body, `load-file-name` may be nil and fall back to `default-directory`, which can point at the wrong directory and silently skip the test.

## Fix

Capture the repo root at top-level when the test file is loaded:

```elisp
(defvar my-test--repo-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name default-directory)))))
```

Then use that constant inside tests.

## Signal

- Test unexpectedly skips
- Path resolves to home directory instead of repo root
- `file-exists-p` guard never reaches assertions
