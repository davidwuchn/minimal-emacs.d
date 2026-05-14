# load-file corrupts nested maphash lambdas in daemon

## Insight 💡

`load-file` corrupts complex defuns with nested `maphash` lambdas when running in Emacs daemon context. The Elisp reader misparses the lambda form, pulling the hash-table argument (e.g., `topics`) into the lambda body instead of placing it as a separate argument to `maphash`.

## Symptom
- `(wrong-number-of-arguments maphash 1)` — hash-table arg consumed by lambda
- `(wrong-number-of-arguments maphash 3)` — trailing variable glued as extra arg
- Specific functions undefined (fboundp nil) while others in same file work

## Pattern
```elisp
;; Source:
(maphash (lambda (topic stats) (let (...) (push ... topic-list)) topics)
;;                                                                  ^^^^^^ hash-table

;; Corrupted by reader:
(maphash (lambda (topic stats) (let (...) (push ... topic-list)) topics))
;;         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
;;         topics ends up inside lambda body, maphash gets 1 arg
```

## Failed fixes
- `eval-buffer` in temp buffer with `lexical-binding t`
- `read` + `eval` of individual forms
- `defalias` in `post-init.el` (read via `load`)
- `after-load-functions` with `eval` of quoted forms

All failed because the Emacs Lisp READER itself corrupts the form.

## Working fix
- Standalone replacement function using `defalias` sent via `emacsclient`
- Bypass ALL corrupted functions entirely
- Re-apply alias via `after-load-functions` hook when file is reloaded

## Context
- Emacs 30+ on macOS (arm64)
- Daemon started with `--fg-daemon` + `MINIMAL_EMACS_WORKFLOW_DAEMON=1`
- File: `gptel-auto-workflow-strategic.el` (2046 lines, `no-byte-compile: t`)
- Stale `.elc` was NOT the cause (deleted, issue persisted)
