# auto-experiment validation fixtures

**Date**: 2026-05-01
**Category**: testing
**Related**: auto-workflow, validation, ERT, worktrees

## Insight

`gptel-auto-experiment-run` validates the real target path before grading. ERT fixtures that drive retry, benchmark, commit, or staging paths must create a minimal target file inside the temp worktree before invoking the runner.

Without the file, `gptel-auto-experiment--validate-code` returns `Missing target file`, causing early validation failure. That masks the behavior under test: retry dispatch counts stay at one, staging callbacks never run, and failures look like dispatcher bugs.

Pattern:

```elisp
(make-directory (file-name-directory target-file) t)
(with-temp-file target-file
  (insert ";;; fixture.el --- test fixture -*- lexical-binding: t; -*-\n"))
```

Prefer real fixture files over stubbing validation when the test is intended to exercise the production experiment flow.
