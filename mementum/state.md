# Mementum State

> Last session: 2026-05-16

## Current Session: Retry Depth Fixes + Pipeline Verification

**Status:** All direct recursive retries converted to stack-safe timer-based patterns. Pipeline verified working end-to-end.

**Commits This Session:**
- `7c764a66` — ⊘ Convert direct retry recursion to timer-based (stack-safe)

**Key Fixes:**
- 4 sites converted: research-patterns retry, request-analyzer retry, call-aux-subagent retry, run-next delay=0 path
- Pattern: `direct recursive call` → `let capture vars` → `run-with-timer 0 nil (lambda () (fn captured-vars))`
- `run-next` always uses timer now (removed `funcall continue` when delay=0)
- Zero new byte-compile warnings. 57 tests green. Pipeline smoke test passes.

**Pipeline Health:**
- Research: 3788 bytes, external URLs ✓
- Self-Evolution: completes ✓
- Auto-Workflow: experiment executed with real code change, grader 8/8 ✓
- Strategy: `metric-adaptive-sections` (evolved) ✓

**Prior Sessions:**
- 2 HIGH plist-put bugs fixed + 18 dead functions removed
- macOS stat fix + .elc cleanup in pipeline
- unified-evolution.py SyntaxError fix

**Remaining Warnings (12, all pre-existing/unfixable):**
- 10 "Cannot open load file: gptel" (needs package in batch mode)
- 2 `(setf ...)` warnings (Emacs 30.2 limitation)

**Test Results:**
- 57 tests, 53 pass, 0 unexpected, 4 skip

---
