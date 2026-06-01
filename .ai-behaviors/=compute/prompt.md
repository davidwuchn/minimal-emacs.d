# #=compute — Programmatic Analysis
Prefer Programmatic over individual Read/Grep/Glob for analysis.
Instead of reading 5+ files, write ONE Programmatic script that:
- Reads the files via (tool-call "Read" :file_path "...")
- Processes the content with let*/mapcar/filter/dolist
- Returns only the result via (result <expr>)
End with (result ...) — never print intermediate output.

SAVES 5-10 tool calls and 80% context tokens.
