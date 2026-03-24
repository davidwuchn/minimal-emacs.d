💡 tdd-first-methodology

## Problem
I was debugging grader timeout issues by trial-and-error, restarting Emacs, and manual testing. This was slow and error-prone.

## Solution
User suggested TDD first. I wrote tests in `tests/test-grader-subagent.el` before fixing code.

## Benefits of TDD Approach

1. **Tests reveal actual behavior** - Tests showed grader was falling back to local grading (4/6 = 66%), not using subagents
2. **Tests document expected behavior** - `grader/model-matches-executor` verifies config consistency
3. **Tests are fast** - Batch tests run in 0.5s vs 90s manual testing
4. **Tests persist** - Future changes will be validated automatically
5. **Tests guide fixes** - Failed tests point directly to what needs fixing

## Test Results

```
Running 5 tests...
   passed  1/5  grader/function-exists
   passed  2/5  grader/local-grading-works
   passed  3/5  grader/model-matches-executor
   passed  4/5  grader/timeout-returns-auto-pass
   passed  5/5  grader/timeout-wrapper-falls-back-cleanly
```

## Discovery

Tests revealed grader IS working, but falling back to local grading. The subagent call succeeds but returns local grading result (4/6 behaviors).

Root cause: `gptel-benchmark-grade` uses `gptel-benchmark-call-subagent` which may not have the agent properly loaded.

## Key Files

- `tests/test-grader-subagent.el` - TDD test suite
- `assistant/agents/grader.md` - Grader config (model: qwen3.5-plus)
- `lisp/modules/gptel-benchmark-subagent.el` - Subagent dispatch
- `lisp/modules/gptel-tools-agent.el` - Timeout wrapper

## λ tdd

```
λ fix(bug). test → red → green → commit
λ verify. emacs --batch -l ert -l test.el --eval "(ert-run-tests-batch-and-exit)"
λ always. test_first > trial_and_error
```