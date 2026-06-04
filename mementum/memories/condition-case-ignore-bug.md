---
title: condition-case (ignore) handler never catches errors
created: 2026-06-05
category: bug-pattern
tags: [elisp, condition-case, error-handling]
---

# condition-case (ignore) is a no-op handler

`(condition-case nil BODY (ignore))` does NOT catch errors. The `ignore`
symbol is not an error condition name — condition-case matches handler
symbols against the signaled error's condition-name. No standard Emacs
error uses `ignore`, so these handlers never trigger.

Fix: `(condition-case nil BODY (error nil))` catches all errors.

Found 28 occurrences across 9 files. The pipeline tried to fix this
in gptel-tools-agent-runtime.el (safe-truename) but the grader
rejected it each time due to the SCORE:X/Y total mismatch bug.
