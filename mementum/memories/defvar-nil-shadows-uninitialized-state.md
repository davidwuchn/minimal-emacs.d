---
title: "defvar nil shadows uninitialized state in cache pattern"
date: 2026-06-16
tags: [elisp, defvar, booleanp, cache, sentinel, datahike]
symbol: 💡
---

# defvar nil shadows uninitialized state in cache pattern

## Bug class

`(defvar FOO nil)` for a "cache" variable shadows the uninitialized state.
`(booleanp nil)` returns `t`, so any `(unless (booleanp FOO) ...)` check 
short-circuits and the function never runs the expensive probe.

## Symptom

Function appears to "work" (no error) but returns `nil` forever, even when 
the underlying check would succeed. All callers see "unavailable" and skip.

## Real example

`ov5-world-store--datahike-pod-available-p` cached Datahike pod availability:

```elisp
(defvar ov5-world-store--datahike-pod-available nil
  "Cached result of Datahike pod availability check.")

(defun ov5-world-store--datahike-pod-available-p ()
  (unless (booleanp ov5-world-store--datahike-pod-available)
    (setq ... (call-process "bb" ...)))
  ov5-world-store--datahike-pod-available)
```

`(booleanp nil)` is `t`, so the `(unless ...)` always skipped the call-process.
Function always returned `nil`, blocking 8 world-store integration tests from
running (they all skipped with "Datahike pod unavailable").

## Fix pattern

Use a non-boolean sentinel for uninitialized state:

```elisp
(defvar ov5-world-store--datahike-pod-available :uninit
  "`:uninit' = not yet probed; t = success; nil = failure.")

(defun ov5-world-store--datahike-pod-available-p ()
  (when (eq ov5-world-store--datahike-pod-available :uninit)
    (setq ... (call-process "bb" ...)))
  ov5-world-store--datahike-pod-available)
```

Note: Use `when` (run when :uninit), not `unless` (run when NOT :uninit).
The latter inverts the logic and would always skip.

## Detection

TDD test: mock `call-process`, set cache to `:uninit`, verify function 
probes and returns `t`. Catches the bug because the test forces the
uninitialized state explicitly.

## Related: makunbound doesn't help

`(makunbound 'FOO)` makes `FOO` void, which causes `(booleanp FOO)` to 
error with `void-variable`. Doesn't help; you must use a sentinel.
