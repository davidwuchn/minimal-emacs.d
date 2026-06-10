---
name: brepl
description: Daemon REPL for Elisp (daemon-repl for OV5) — evaluate Elisp code in a running Emacs daemon, validate brackets before save, auto-evaluate files on change
metadata:
  molecules: [daemon-repl, elisp, repl, emacsclient]
  level: compound
---

# Daemon REPL for OV5

> **Not** the Clojure `brepl` CLI tool. This is the Elisp daemon REPL for OV5.
> For Clojure nREPL, use `~/.local/bin/brepl` instead.

brepl brings bracket-fixing REPL concepts from ClojureScript to Emacs Lisp in OV5. It enables AI agents to safely generate, validate, and evaluate Elisp code.

## Concepts

- **Bracket fixing**: Validate and auto-fix unbalanced parentheses before saving `.el` files
- **Daemon REPL**: Evaluate expressions via `emacsclient` in a running Emacs daemon
- **Auto-eval**: Watch `.el` files and automatically evaluate them after save
- **Self-heal integration**: On evaluation failure, trigger OV5 self-healing

## Usage

### Evaluate Expression

```elisp
(gptel-daemon-repl-eval-expression "(+ 1 2 3)")
```

Returns result as string, or signals error if daemon is not running.

### Evaluate File

```elisp
(gptel-daemon-repl-eval-file "lisp/modules/foo.el")
```

Loads the file in the daemon. Reports success/failure.

### Validate Brackets

```elisp
(gptel-daemon-repl-validate-brackets "(defun foo () 42")
```

Returns plist:
- `:valid` — t if balanced
- `:fixed-content` — auto-fixed string (if fixable)
- `:error` — error message (if unfixable)

### Check Status

```elisp
(gptel-daemon-repl-status)
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

brepl auto-discovers Emacs daemon sockets:

1. `/tmp/emacs$(id -u)/` — macOS/Linux default
2. `${TMPDIR}/emacs$(id -u)/` — macOS with custom TMPDIR
3. `~/.emacs.d/server/` — fallback

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
