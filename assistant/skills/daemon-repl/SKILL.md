---
name: daemon-repl
description: "Daemon REPL for Elisp — evaluate Elisp code in a running Emacs daemon via emacsclient, validate brackets before save, auto-evaluate .el files on change. Use when you need to run Elisp from outside Emacs, check daemon status, or validate Elisp syntax."
metadata:
  molecules: [daemon-repl, elisp, repl, emacsclient]
  level: compound
---

# Daemon REPL for OV5

> **Not the Clojure `brepl` CLI tool.** This is the Elisp daemon REPL for OV5. These two skills have similar names but different tools:
> - `daemon-repl` (this skill) — Elisp evaluation via emacsclient
> - `brepl` (see that skill) — Clojure nREPL client via babashka

brepl brings bracket-fixing REPL concepts from ClojureScript to Emacs Lisp in OV5. It enables AI agents to safely generate, validate, and evaluate Elisp code.

## Emacsclient Bash Pattern (for opencode agents)

When calling from outside Emacs (e.g., from a shell or an agent), use this pattern:

```bash
emacsclient -s /tmp/emacs$(id -u)/pmf-value-stream -a false --eval "$(cat <<'EOF'
(gptel-daemon-repl-status)
EOF
)"
```

**Safety rules:**
- Always use `-a false` so `emacsclient` never auto-spawns a daemon.
- Always use heredoc (`<<'EOF'`) for Elisp quoting — prevents shell variable expansion.
- Wrap multi-form code in `progn`.

For a different server name, replace `pmf-value-stream` with your daemon name. For the default `server` daemon:

```bash
emacsclient -s /tmp/emacs$(id -u)/server -a false --eval "$(cat <<'EOF'
(gptel-daemon-repl-status)
EOF
)"
```

## Concepts

- **Bracket fixing**: Validate and auto-fix unbalanced parentheses before saving `.el` files
- **Daemon REPL**: Evaluate expressions via `emacsclient` in a running Emacs daemon
- **Auto-eval**: Watch `.el` files and automatically evaluate them after save
- **Self-heal integration**: On evaluation failure, trigger OV5 self-healing

## Usage

### Evaluate Expression (Elisp API)

For Emacs-internal use:

```elisp
(gptel-daemon-repl-eval-expression "(+ 1 2 3)")
```

Returns result as string, or signals error if daemon is not running.

### Evaluate Expression (emacsclient)

From outside Emacs:

```bash
emacsclient -s /tmp/emacs$(id -u)/server -a false --eval "$(cat <<'EOF'
(gptel-daemon-repl-eval-expression "(+ 1 2 3)")
EOF
)"
```

### Evaluate File (Elisp API)

```elisp
(gptel-daemon-repl-eval-file "lisp/modules/foo.el")
```

Loads the file in the daemon. Reports success/failure.

### Evaluate File (emacsclient)

```bash
emacsclient -s /tmp/emacs$(id -u)/server -a false --eval "$(cat <<'EOF'
(gptel-daemon-repl-eval-file "lisp/modules/foo.el")
EOF
)"
```

### Validate Brackets (Elisp API)

```elisp
(gptel-daemon-repl-validate-brackets "(defun foo () 42")
```

Returns plist:
- `:valid` — t if balanced
- `:fixed-content` — auto-fixed string (if fixable)
- `:error` — error message (if unfixable)

### Check Status

Elisp API:

```elisp
(gptel-daemon-repl-status)
```

emacsclient:

```bash
emacsclient -s /tmp/emacs$(id -u)/server -a false --eval "$(cat <<'EOF'
(gptel-daemon-repl-status)
EOF
)"
```

Returns plist with:
- `:enabled` — is brepl active?
- `:server-accessible` — is daemon socket reachable?
- `:socket-dir` — where sockets are found
- `:watches` — number of active directory watches

### Interactive Status Buffer

```elisp
M-x gptel-daemon-repl-show-status
```

Opens `*brepl-status*` buffer with full diagnostics.

## Configuration

```elisp
(setq gptel-daemon-repl-enabled t)              ; Master switch
(setq gptel-daemon-repl-eval-on-save t)         ; Auto-eval after save
(setq gptel-daemon-repl-validate-brackets t)    ; Fix brackets before save
(setq gptel-daemon-repl-socket-dir nil)         ; Auto-detect if nil
(setq gptel-daemon-repl-default-server "server") ; Server name
```

## Integration with OV5

### Edit Tool Hook

When an AI agent edits an `.el` file via the Edit tool:

1. **Before save**: `gptel-daemon-repl-validate-brackets` checks syntax
2. **Auto-fix**: If unbalanced, fixes are applied automatically
3. **After save**: File is evaluated via `emacsclient`
4. **On failure**: `gptel-auto-workflow--self-heal-semantic` is triggered

### Experiment Workflow

When OV5 experiments generate new Elisp:

```elisp
;; After writing experiment output
(gptel-daemon-repl-eval-file experiment-file)
;; → If error, self-heal fixes syntax/runtime issues
;; → If success, file is ready for commit
```

### Error Recovery

Evaluation errors trigger the self-healing pipeline:

1. brepl detects eval failure
2. Calls `gptel-auto-workflow--self-heal-semantic` on the file
3. Self-heal audits, fixes syntax, re-evaluates
4. Loop continues until file loads cleanly

## Socket Discovery

brepl auto-discovers Emacs daemon sockets in this order (from `gptel-ext-daemon-repl.el` lines 71-88):

1. `server-socket-dir` (Emacs 29+ built-in)
2. `/run/user/$UID/emacs/` (XDG, Linux)
3. `/tmp/emacs$UID/` (standard, macOS/Linux)
4. `${TMPDIR}/emacs$UID/` (macOS with custom TMPDIR)
5. `~/.emacs.d/server/` (fallback)

Override with `gptel-daemon-repl-socket-dir`.

## File Watch

brepl watches `lisp/modules/` for `.el` changes:

```elisp
(gptel-daemon-repl-watch-directory "lisp/modules/")
```

Only evaluates:
- `.el` files (not `.elc`, not autoloads)
- Not in `tests/` directories
- Not dotfiles

## Requirements

- Emacs daemon running (`emacs --daemon` or server-start)
- `emacsclient` in PATH
- `file-notify` support (for auto-eval watch)

## Files

- `lisp/modules/gptel-ext-daemon-repl.el` — main module
- `tests/test-daemon-repl.el` — test suite
- Loaded via `lisp/gptel-config.el`

## Related Skills

- `brepl` — Clojure nREPL client (separate tool, similar name — don't confuse)
- `ov5` — OV5 cowork guide (pipeline, researcher, evolution)
- `ov5-status` — focused system health check
