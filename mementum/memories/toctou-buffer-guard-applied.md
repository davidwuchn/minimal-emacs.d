TOCTOU buffer guards applied in gptel-auto-workflow-projects.el:
- `gptel-auto-workflow-list-project-buffers`: Added `(when (and buf (buffer-live-p buf))` guard + scoped `ignore-errors` around `with-current-buffer` only + proper empty mode name handling with `string-empty-p`
- `gptel-auto-workflow-clear-executor-overlays`: Added same TOCTOU guard in the all-projects lambda path

Pattern: defense-in-depth at use site, not just in iterator. Iterator checks `buffer-live-p` but buffer can be killed between check and lambda execution.