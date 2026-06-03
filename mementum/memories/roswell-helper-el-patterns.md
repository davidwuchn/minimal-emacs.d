## Roswell helper.el Core Patterns (early-exploration)

File: `lisp/helper.el` - Emacs init for Roswell (Common Lisp impl manager)

### Patterns
- Shell-command coupling: `shell-command-to-string` + `(substring ... 0 -1)` for newline trim
- Config parsing: Manual regex on tab-delimited `~/.roswell/config`
- Conditional init: Top-level `let` selects SLIME vs SLY at load time
- String-built Lisp code: `roswell-load` constructs Lisp forms as shell strings

### Anti-patterns / Risks
1. **Fragile trim**: `(substring s 0 -1)` crashes on empty string
2. **No search guard**: `re-search-forward` failure leaves `match-string` undefined
3. **No file existence check**: `insert-file-contents` on missing config signals error
4. **Top-level side effects**: `let` runs unconditionally at load
5. **Hard-coded SBCL**: `roswell-load` forces `-L sbcl-bin`

### Improvement candidates
- Extract `trim-newline` helper with empty-string guard
- Wrap `re-search-forward` in `when` before `match-string`
- Use `file-exists-p` before reading config
- Convert top-level `let` to `defun roswell-setup` for explicit invocation
- Parameterize Lisp implementation in `roswell-load`