## Applied: Extracting nested `let*` + `setq` into named functions

In `gptel-auto-experiment--make-kept-result-callback` (gptel-tools-agent-prompt-build.el), extracted two pure functions from inline logic:

1. `gptel-auto-experiment--failure-reason` - converts arg to string, guards nil via `(and arg (symbolp arg))` (critical: `symbolp` returns `t` for nil in Elisp!)
2. `gptel-auto-experiment--downgrade-exp-result` - copies plist, sets three keys, non-list guard

Benefits: Testable independently, docstrings capture assumptions, main function becomes declarative orchestration. Byte-compile clean — no new warnings.

**Emacs Lisp caveat**: `(symbolp nil)` is `t` — always guard nil-explicitly with `(and arg (symbolp arg))` when matching symbols.