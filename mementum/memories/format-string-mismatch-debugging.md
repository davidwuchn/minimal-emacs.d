---
title: "Format String Mismatch in gptel-auto-experiment-build-prompt"
status: active
category: patterns
tags: [emacs-lisp, format-strings, debugging, gptel, auto-workflow]
related: [self-evolution, debugging-protocol]
---

## Problem

The headless workflow daemon (`copilot-auto-workflow`) was failing with `(void-variable "%s")` errors during experiment execution. This broke subagent callbacks and prevented the auto-workflow from running experiments.

## Root Cause

`gptel-auto-experiment-build-prompt` in `lisp/modules/gptel-tools-agent-prompt-build.el` had a format string mismatch:
- 19 format specifiers in the string template
- 20+ arguments passed to `format`
- The `%%s` escaping for a shell command inside the prompt was being double-processed by `format`

Additionally, `gptel-auto-experiment-run` in `lisp/modules/gptel-tools-agent-experiment-core.el` was calling `my/gptel--run-agent-tool-with-timeout` with missing required arguments (`agent-name` and `description`), causing `wrong-number-of-arguments` errors.

## Secondary Issue: Stale Compiled Definitions

The daemon had stale byte-compiled closures referencing old function signatures and debug wrappers (`my/debug-wrap`, `my/debug-around-agent-task-timeout`) that had been removed from source but persisted in memory. Even after reloading `.el` files, old closures inside `gptel-auto-experiment-run` continued to call the old signatures.

## Solution

1. **Fixed format string**: Rebuilt `gptel-auto-experiment-build-prompt` with correct argument alignment and proper `%%s` escaping
2. **Fixed argument mismatch**: Added missing `"executor"` and `"Validation retry"` arguments to all `my/gptel--run-agent-tool-with-timeout` call sites
3. **Purged daemon state**: 
   - Removed all `.elc` compiled files
   - Restarted daemon
   - Reloaded all modules fresh
   - Removed stale debug wrapper functions with `fmakunbound`

## Key Insight

When debugging Elisp in a long-running daemon:
- `load`ing a `.el` file does NOT replace closures already bound in lambda expressions
- Old closures retain references to removed functions (causing `void-function` errors)
- Byte-compiled `.elc` files can cache old definitions even after source changes
- **Best practice**: Delete all `.elc` files and restart the daemon when making signature changes

## Files Modified

- `lisp/modules/gptel-tools-agent-prompt-build.el` - Fixed format string/argument mismatch
- `lisp/modules/gptel-tools-agent-experiment-core.el` - Added missing arguments to `run-agent-tool-with-timeout` calls

## Verification

- `gptel-auto-experiment-build-prompt` returns valid prompt strings
- `my/gptel--run-agent-tool-with-timeout` accepts correct 5+ argument signatures
- Experiment run starts without `(void-variable "%s")` or `wrong-number-of-arguments` errors
