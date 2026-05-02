# mise ripgrep tooling

**Date**: 2026-05-01
**Updated**: 2026-05-02
**Category**: tooling
**Related**: search, rg, mise, opencode

## Insight

This workspace removed the broken `/home/davidwu/.cargo/bin/rg` binary because it was incompatible with Pi5/Debian 16KB pages. The OpenCode `Grep` and `Glob` tools may still try that exact path and fail with `ChildProcess.spawn (/home/davidwu/.cargo/bin/rg ...)`.

## Current rg Location

Always use `which rg` to find the correct path dynamically:

```bash
which rg
# → /home/davidwu/.local/share/mise/installs/cargo-ripgrep/latest/bin/rg
```

This is the mise-managed ripgrep installation. Never hardcode rg paths.

## Usage Patterns

### Bash searches (preferred)
```bash
# Find rg first, then use it
RG=$(which rg)
$RG pattern files...

# Or use mise exec
mise exec cargo:ripgrep -- rg ...
```

### Emacs Lisp
```elisp
;; Use executable-find for dynamic lookup
(executable-find "rg")
```

## Fix for OpenCode Tools

OpenCode `Grep`/`Glob` tools hardcode `~/.cargo/bin/rg`. Create a symlink:

```bash
mkdir -p ~/.cargo/bin
ln -sf $(which rg) ~/.cargo/bin/rg
```

This resolves the issue without modifying OpenCode's SDK.

## What Not To Do

- Do NOT hardcode `/home/davidwu/.local/share/mise/installs/cargo-ripgrep/latest/bin/rg` (may change)
- Do NOT rely on OpenCode tools without the symlink fix

## Detection

If file/content search fails unexpectedly, check whether `~/.cargo/bin/rg` exists and points to the correct binary.
