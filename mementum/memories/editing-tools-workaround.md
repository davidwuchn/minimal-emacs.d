## Edit tool string matching workaround

The `Edit` tool with exact string matching may fail with "Symbol's value as variable is void: n" error when the `old_str` contains Emacs Lisp with certain patterns (e.g., backslash-escaped double quotes in docstrings, or certain character combinations).

**Workaround**: Use Python's `str.replace()` via Bash to perform the replacement when the Edit tool fails. Steps:
1. Read the exact text from the file
2. Write a Python script that reads the file, replaces the exact string, and writes back
3. Verify paren balance with `scan-sexps`
4. Run byte-compile