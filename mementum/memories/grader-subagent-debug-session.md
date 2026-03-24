💡 grader-subagent-debug-session

## Problem
Grader subagent always fell back to local grading, never used LLM.

## Root Cause Chain
1. `gptel-tools-agent.el` did NOT require `gptel-agent`
2. `gptel-agent--task` was never defined (fboundp returned nil)
3. `gptel-agent--agents` was declared nil (shadowing)
4. `(fboundp 'gptel-agent--task)` → nil → local grading fallback

## TDD Approach
1. Wrote tests first: `tests/test-grader-subagent.el`
2. Tests revealed actual behavior
3. Tests guided fix
4. Tests verify fix works

## Fixes Applied
1. `(require 'gptel-agent)` at top of `gptel-tools-agent.el`
2. Removed redundant `(defvar gptel-agent--agents nil)`
3. Fixed JSON parser to handle grader output format

## Verification
```
:gptel-agent-loaded t
:gptel-agent--task-fbound t  
:gptel-agent--agents-count 13
:grader-model "qwen3.5-plus"
:executor-model "qwen3.5-plus"
```

## Key Files
- `lisp/modules/gptel-tools-agent.el` - Added require
- `lisp/modules/gptel-benchmark-subagent.el` - Fixed JSON parser
- `tests/test-grader-subagent.el` - 8 tests, all pass

## λ debug
```
λ bug. test → red → trace → fix → green
λ verify. ./scripts/run-tests.sh grader
```