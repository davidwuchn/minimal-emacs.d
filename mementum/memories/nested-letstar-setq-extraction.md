## Pattern: Extracting nested `let*` + `setq` into named functions

In `gptel-auto-experiment--make-kept-result-callback`, the downgrade logic and failure-reason parsing were inline in a deeply nested `let*` using `setq` to mutate bindings.

**Refactoring**: Extracted two pure functions:
1. `gptel-auto-experiment--failure-reason` - converts arg to string, guards nil via `(and arg (symbolp arg))` (critical: `symbolp` returns `t` for nil in Elisp!)
2. `gptel-auto-experiment--downgrade-exp-result` - copies plist, sets three keys, non-list guard

**Benefits**: Testable independently, docstrings capture assumptions, main function becomes declarative orchestration.

**Emacs Lisp caveat**: `(symbolp nil)` is `t` - always guard nil-explicitly with `(and arg (symbolp arg))` when matching symbols.