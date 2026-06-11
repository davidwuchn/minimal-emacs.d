---
name: brepl
description: "Clojure REPL client (nREPL-based, Babashka). Use for evaluating Clojure code, loading Clojure files, fixing unbalanced brackets, and interactive nREPL work. Not the Elisp daemon-repl."
---

# brepl — Clojure nREPL Client

> **MANDATORY: You MUST load this skill before using `brepl`.** This skill contains the heredoc patterns, prerequisites, and troubleshooting needed to use brepl correctly.
>
> **Not the Elisp daemon-repl.** This is the Clojure `brepl` CLI tool (github.com/licht1stein/brepl), a babashka-based nREPL client. For the Elisp daemon eval module, see the `daemon-repl` skill.

## Overview

brepl is a REPL client for evaluating Clojure expressions via nREPL. It connects to an nREPL server using `.nrepl-port` or `BREPL_PORT` environment variable.

## Heredoc Pattern — Default Approach

**Always use heredoc for brepl evaluation.** This eliminates quoting issues.

### Syntax (Stdin — Recommended)

```bash
brepl <<'EOF'
(your clojure code here)
EOF
```

Use `<<'EOF'` (quoted) to prevent shell variable expansion.

### Alternative: Captured Output with $(cat)

When you need to capture brepl output into a variable or pipe it:

```bash
brepl "$(cat <<'EOF'
(your clojure code here)
EOF
)"
```

Prefer the plain stdin heredoc (`<<'EOF'`) for most cases. Use the `$(cat)` wrapper only when you need to capture or redirect output.

### Alternative: Positional Argument (simple one-liners only)

```bash
brepl '(+ 1 2 3)'
```

### Load a File

```bash
brepl -f src/myapp/core.clj
```

### Fix Unbalanced Brackets

```bash
# Fix file in place
brepl balance src/myapp/core.clj

# Preview fix to stdout
brepl balance src/myapp/core.clj --dry-run
```

## Examples

**Namespace reload + call:**
```bash
brepl <<'EOF'
(require '[myapp.core] :reload)
(myapp.core/some-function "test" 123)
EOF
```

**Run tests:**
```bash
brepl <<'EOF'
(require '[clojure.test :refer [run-tests]])
(require '[myapp.core-test] :reload)
(run-tests 'myapp.core-test)
EOF
```

**Error inspection:**
```bash
brepl <<'EOF'
*e
(require '[clojure.repl :refer [pst]])
(pst)
EOF
```

## Critical Rules

1. **Always use heredoc** — one pattern, no quoting surprises
2. **Quote the delimiter** — `<<'EOF'` not `<<EOF`
3. **No escaping needed** — write Clojure code naturally between delimiters
4. **Multi-step operations** — combine multiple forms in one heredoc block
5. **Ensure nREPL server is running** — brepl connects via `.nrepl-port` or `BREPL_PORT`

## Prerequisites

- `~/.local/bin/brepl` must be installed (babashka binary)
- An nREPL server must be running (e.g., `clj -M:nrepl` or `lein repl`)
- `.nrepl-port` file or `BREPL_PORT` env var must point to the server port

## Troubleshooting

### "No nREPL port found"

brepl looks for the nREPL port in two places:

1. **`.nrepl-port` file** — creates this file in the project root. Verify it exists and contains a valid port number:
   ```bash
   cat .nrepl-port
   ```
   If missing, restart your nREPL server (e.g., `clj -M:nrepl` or `lein repl`).

2. **`BREPL_PORT` environment variable** — override the port:
   ```bash
   export BREPL_PORT=7888
   ```
   Useful when `.nrepl-port` is in a different directory or you're connecting to a remote nREPL.

If neither works, confirm the nREPL server is actually running and listening on the expected port.
