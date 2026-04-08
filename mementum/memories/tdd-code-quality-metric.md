# TDD Approach for Code Quality Metric

## Insight
Used TDD to improve code quality metric that was discarding valid experiments.

## Problem
Old metric weighted docstrings at 40%, penalizing generated code without docs. Code scoring 0.83 before could drop to 0.51 after changes, triggering discard even when eight-keys score was high.

## Solution
1. **Write tests first**: Created 6 new tests in test-grader-subagent.el for:
   - `gptel-benchmark--positive-patterns-score` function existence
   - Error handling rewards
   - Bad naming penalties
   - Type predicate rewards
   - Weight distribution verification
   - Minimum score threshold (≥0.70 for good patterns without docs)

2. **Run tests to see failures**: All 6 tests failed as expected

3. **Implement**: Added `gptel-benchmark--positive-patterns-score` function scoring:
   - Error handling (40%): condition-case, user-error, error, signal
   - Naming conventions (30%): penalizes my-, foo-, bar- prefixes
   - Standard predicates (30%): null, stringp, listp, etc.

4. **Rebalance weights**: Docstrings 20% → Positive 30% → Length 25% → Complexity 25%

5. **Verify**: All tests pass (1303 tests, 0 unexpected)

## Result
Code with good patterns but no docstrings now scores ≥0.70 instead of 0.51. Valid experiments with error handling and type checking won't be discarded.

## Pattern
TDD cycle: test → fail → implement → pass. Tests encode requirements before code exists.