# Daemon Persistence Anti-Pattern

**Date**: 2026-04-02
**Category**: anti-pattern
**Related**: daemon, elc, compilation

## Anti-Pattern

Compiled `.elc` files persist across daemon restarts, causing stale code.

## Problem

1. Make changes to `.el` file
2. Restart daemon
3. Changes not reflected
4. Old compiled code still running

## Root Cause

- Emacs daemon loads `.elc` if it exists
- Restarting daemon doesn't recompile
- Stale `.elc` files persist

## Solution

```bash
# Remove all compiled files
rm -f lisp/modules/*.elc

# Kill all Emacs processes
killall -9 Emacs

# Remove temp files
rm -rf /tmp/emacs*

# Start fresh daemon
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 emacs --bg-daemon=copilot-auto-workflow
```

## Prevention

### Option 1: Never compile
```elisp
;; In file header
;; -*- no-byte-compile: t; -*-
```

### Option 2: Auto-recompile
```elisp
;; In early-init.el
(setq load-prefer-newer t)  ; Prefer .el over .elc
```

### Option 3: Clean before restart
```bash
# Always clean before daemon restart
find . -name "*.elc" -delete
```

## Signal

- Changes not reflected after restart
- Debugging shows old code
- Works in new Emacs but not daemon
- Behavior different from fresh start

## Test

```bash
# Verify fresh code
rm -f lisp/modules/*.elc
emacs --batch -l lisp/modules/module.el -f some-function
```