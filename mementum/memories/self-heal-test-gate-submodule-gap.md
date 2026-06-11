# Self-Heal Test Gate Was Broken: Submodules Not Hydrated in Worktrees

## Insight
`run-ert-in-worktree` (the test gate we added to self-heal-file-via-ov5) was broken in production because git worktrees don't include submodule checkouts. The test runner (`scripts/run-tests.sh`) fails on a bare worktree with `void-function gptel--make-backend` because `packages/gptel/` is empty.

The existing mocks masked this: they used synthetic mock scripts, not the real test runner. Only by running `run-tests.sh` in an actual detached worktree did the failure surface.

## Fix
Removed `run-ert-in-worktree` from the self-heal path. Self-heal makes structural fixes (blank lines, parens, fboundp guards) validated by `check-parens` + `load-file`. The full test suite gate belongs in the staging path (`verify-staging`) which already hydrates submodules before running tests.

## Lesson
- Mock tests that don't use the real test runner can mask integration failures
- Git worktrees don't include submodule checkouts by default
- Test gates must be placed where the environment supports them (staging has hydration, self-heal doesn't)
- `verify-staging` (line 438 of staging-merge.el) calls `hydrate-staging-submodules` before tests — this is the correct location for the test gate
