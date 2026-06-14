💡 **self-heal fixers can corrupt string literals silently.** `gptel-auto-workflow--fix-docstring-width` word-wrapped ANY long string literal followed by `(` or `)`, not just docstrings. It split regex strings like the kibcm-patterns `(:K "remove nil\\|unless nil ...")` by inserting literal newlines mid-string whenever the content had spaces.

**Why the safety net missed it:** `run-fixer-with-rollback` only rolls back when `check-parens` fails. Corruption inside a string literal keeps parens balanced, so the broken file persisted.

**Why it was invisible in isolation:** the fixer only ran during the FULL byte-compiler self-heal, which a test triggered unmocked via `gptel-auto-workflow-run-async`. Single-file test runs never invoked it, so kibcm tests passed alone but failed ~90s into the full suite.

**Fix:** added `gptel-auto-workflow--docstring-position-p` — check the enclosing form's head symbol (`def*`/`define-*`/`cl-def*`) before wrapping. Keyword-headed forms `(:K ...)` are data, not docstrings.

**Pattern to recall:** any self-heal fixer that mutates string content must (1) distinguish docstrings from data strings, (2) verify semantic integrity, not just paren balance. The same bug class likely lurks in other string-touching fixers (`fix-unescaped-quotes`, etc.). Test with space-containing regex literals, not space-free ones — space-free strings word-wrap to a single "word" and don't reproduce.
