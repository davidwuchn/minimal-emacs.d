# Pre-Push Hook Fix

## Issue
Pre-push hook failed when submodules had new commits, reporting "non-fast-forward" errors even when commits were already pushed.

## Root Cause
1. `git push origin "$default_branch"` fails from detached HEAD (not on any branch)
2. Verification checked wrong commit hash after rebase
3. "Everything up-to-date" case was treated as error

## Fix
```bash
# Changed from:
git push origin "$default_branch"

# To:
git push origin HEAD:"$default_branch"
```

Also removed post-push verification step (git exit code is sufficient).

## Files
- `.git/hooks/pre-push` (installed)
- `scripts/git-hooks/pre-push` (tracked source)

## Status
✅ Fixed 2026-03-28, commit 77578d8