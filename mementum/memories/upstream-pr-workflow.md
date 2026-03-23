# Upstream PR Workflow

## Insight

When local defensive code reveals an upstream bug, extract the minimal fix for PR, keep defensive layers local.

## Workflow

```
λ pr_workflow(x).    discover(bug) → check(upstream_has_fix)
                     | ¬upstream_has_fix → create_branch(upstream/master)
                     | implement(minimal_fix) > defensive_framework
                     | commit(clear_message) → push(fork)
                     | gh_pr_create(upstream_repo) → wait_review
```

## Commands

```bash
# 1. Fetch latest upstream
git fetch upstream

# 2. Create clean branch from upstream
git checkout -b fix-<issue> upstream/master

# 3. Implement minimal fix (not defensive framework)

# 4. Commit with conventional message
git commit -m "Fix: <description>"

# 5. Push to fork
git push origin fix-<issue> -u

# 6. Create PR
gh pr create --repo <upstream-owner>/<upstream-repo> \
             --head <fork-owner>:fix-<issue> \
             --base master \
             --title "Fix: <description>" \
             --body "<problem>\n<root-cause>\n<solution>\n<testing>"
```

## PR Template Sections

1. **Problem** — What breaks, when, for whom
2. **Root Cause** — Why it happens (code-level)
3. **Solution** — What changed and why
4. **Testing** — How it was verified

## Minimal vs Defensive

| Approach | Upstream | Local |
|----------|----------|-------|
| Fix bug in happy path | ✅ PR | — |
| Add edge case handling | ⚠️ Maybe | ✅ Keep |
| Defensive safety net | ❌ No | ✅ Keep |
| Framework for resilience | ❌ No | ✅ Keep |

## Example PR

**PR #1305** — gptel nil/null tool names
- Core fix: `cond` instead of `if` in streaming parser
- Left local: `my/gptel--sanitize-tool-calls`, doom-loop detection
- Result: 20 lines added, 16 deleted, clean fix

## Captured

2026-03-23 — From PR #1305 for gptel nil/null tool names