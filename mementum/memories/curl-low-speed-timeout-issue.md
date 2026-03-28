# Curl Low-Speed Timeout Issue

**Discovered**: 2026-03-28

## Problem

Auto-workflow failing with curl exit code 28 (timeout) even when backend
configured with `--max-time 600` or `--max-time 900`.

## Root Cause

Global `gptel-curl-extra-args` included `-y 15 -Y 50`:
- `-y 15`: 15 seconds of low-speed allowed before abort
- `-Y 50`: 50 bytes/sec threshold

When LLM thinks for >15s without streaming output, curl aborts with
exit 28 regardless of `--max-time` setting. Low-speed detection is
independent of max-time.

Curl args are appended: `global → backend`. Backend `--max-time`
overrides, but `-y/-Y` from global still active.

## Fix

Removed `-y/-Y` from `my/gptel--install-fast-curl-timeouts` in
`gptel-ext-abort.el`. Low-speed timeout causes false positives for
subagents; backend-specific timeouts handle long-running calls.

Also added `1013` and `server is initializing` to transient error
patterns for Moonshot API cold starts.

## Files Changed

- `lisp/modules/gptel-ext-abort.el`: Remove -y/-Y from global args
- `lisp/modules/gptel-ext-backends.el`: DashScope 600s → 900s
- `lisp/modules/gptel-ext-retry.el`: Add 1013 to transient patterns

## Lesson

Curl has multiple timeout mechanisms:
1. `--connect-timeout`: Connection phase only
2. `--max-time`: Total operation time
3. `-y/-Y`: Low-speed detection (independent of max-time!)

For long-running API calls, remove low-speed detection or set very
generous thresholds.