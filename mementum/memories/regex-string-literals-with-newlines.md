# Regex strings with embedded newlines change behavior

In Emacs Lisp, a newline inside a regex string is not formatting: it is a real character in the pattern. That can silently break matching when a pattern is split across lines for readability.

For pattern constants, prefer single-line regex strings or `concat`-built fragments. Do not rely on blank-line audits to catch this class; they often skip string literals by design.
