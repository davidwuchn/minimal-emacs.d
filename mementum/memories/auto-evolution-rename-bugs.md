---
symbol: 💡
title: Auto-evolution pipeline renames params/special forms to suppress warnings
category: ai-pipeline
tags: [pipeline, auto-evolution, byte-compile, lisp, renames]
related: [save-excursion-does-not-preserve-match-data, format-string-mismatch-debugging]
---

# Auto-evolution pipeline renames params and special forms to suppress warnings

**Insight:** The OV5 auto-evolution pipeline (Pi5 daemon) attempts to suppress
byte-compile warnings by:
1. Adding `(defvar X nil)` for "free variables" (sometimes legitimate)
2. Renaming function parameters from `X` to `_X` (often broken)
3. Renaming special forms: `if → _if`, `let → _let`, `let* → _let*`,
   `when → _when`, `if-let* → _if-let*` (always broken)

**Failure modes:**

1. **Parameter renamed, body unchanged:** The body still uses the old name `X`,
   but the parameter is now `_X`. The function reads the global `X` (set to nil
   by the defvar) instead of the parameter. TDD test: existing behavioral tests
   fail with unexpected return values (e.g., `register-id` returns nil).
   - Example: `my/gptel--fsm-register (fsm)` → `my/gptel--fsm-register (_fsm)`,
     with body `(when (and fsm ...))` that reads global `fsm` (nil).

2. **Special form renamed:** `(if A B C)` becomes `(_if A B C)`. The first time
   the function is called, error: `Symbol's function definition is void: _if`.
   - TDD test: function call fails immediately with void-function error.
   - Example: `(_if (executable-find "wc") ...)` instead of `(if ...)`.

**Detection:**

- Existing behavioral tests fail with:
  - `(stringp nil)` errors (param-shadow pattern)
  - `Symbol's function definition is void: _if/_let/_when/_cond` (special-form rename)
  - "FSM registry invariant violated: FSM→ID bidirectional mismatch" (fsm hash)
- Static analysis: scan for `(defvar X nil)` at file top + `(_X ...)` in any
  function signature in same file = likely bug.

**Fix:** Revert the auto-fix. Do NOT try to "fix" the rename by adding more
defvars or remapping. The right fix is to remove the broken renames and let
any legitimate warnings stay as warnings.

**Defensive TDD tests:**

- `test-fsm/register-id` already catches the param-shadow pattern.
- New: `test-strategic/filter-large-files-no-void-functions` catches the
  special-form rename pattern (calls a function that uses `if`, expects
  list result, not void-function error).

**Source:** Discovered 2026-06-16 during a sync-with-remote session. The
auto-evolution pipeline had touched 12+ lisp modules, with the rename pattern
appearing in lisp/modules/gptel-ext-fsm-utils.el, gptel-auto-workflow-strategic.el,
gptel-auto-workflow-self-heal-semantic.el, gptel-ext-checkpoint.el,
gptel-ext-retry.el, gptel-ext-transient.el, gptel-tools-agent-experiment-core.el,
gptel-tools-agent-prompt-build.el, gptel-tools-memory.el, gptel-tools-code.el,
gptel-tools-grep.el, gptel-auto-workflow-pipeline-statechart.el,
gptel-auto-workflow-recovery.el, nucleus-tools-validate.el. All reverted.

**Workaround for static analysis:** A linter could detect
`(defvar X nil)` + `(_X ...)` in the same file as a red flag. But behavioral
tests are more reliable.
