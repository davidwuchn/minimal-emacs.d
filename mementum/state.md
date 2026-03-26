# Mementum State

> Last session: 2026-03-26 15:00

## Total Improvements: 65+ Real Code Fixes

249 commits since March 25, 2026.

### Recent Fixes (Last 25)

| # | File | Fix |
|---|------|-----|
| 65 | gptel-ext-context.el | Eliminate duplicate token counting |
| 64 | eca-security.el | Fix temp directory path |
| 63 | gptel-ext-context-cache.el | Replace regex with string-prefix-p |
| 62 | gptel-auto-workflow-strategic.el | Extract validation logic into helper |
| 61 | gptel-auto-workflow-strategic.el | Validate-and-add-target returns nil |
| 60 | gptel-auto-workflow-strategic.el | Remove extra closing paren |
| 59 | gptel-benchmark-core.el | Fix destructive nreverse |
| 58 | gptel-ext-context-cache.el | Fix metadata cache inconsistency |
| 57 | gptel-ext-context-cache.el | Use full metadata cache |
| 56 | gptel-benchmark-core.el | Fix inconsistent indentation |
| 55 | gptel-tools-code.el | Extract tree-sitter validation helper |
| 54 | gptel-auto-workflow-strategic.el | Fix JSON parsing bug |
| 53 | gptel-auto-workflow-strategic.el | Fix regex fallback for subdirs |
| 52 | gptel-ext-retry.el | Handle list content in strip-images |
| 51 | gptel-benchmark-core.el | Fix nreverse in two functions |
| 50 | gptel-benchmark-core.el | Fix destructive nreverse in trend |
| 49 | gptel-ext-context.el | Fix preview/replace branch logic |
| 48 | gptel-ext-context.el | Refactor auto-compact-needed-p |
| 47 | gptel-ext-context-cache.el | Extract cache-or-alist-lookup helper |
| 46 | gptel-ext-context.el | Optimize token calculation |
| 45 | gptel-agent-loop.el | Add fboundp safety check |
| 44 | gptel-agent-loop.el | Extract overlay cleanup into helper |
| 43 | gptel-agent-loop.el | Extract abort check into helper |
| 42 | gptel-benchmark-core.el | Extract score extraction helper |

---

## Current Issue

**Reviewer API errors:**

1. **Curl exit code 28** - timeout (needs longer timeout or faster model)
2. **"thinking is enabled but reasoning_content is missing"** - DashScope API error

The reviewer uses `qwen3.5-plus` on DashScope with 600s timeout.

---

## λ Summary

```
λ subscriptions. DashScope (8) + moonshot (2)
λ parallel. macOS (daylight) + Pi5 (24/7 Linux)
λ dynamic. LLM selects targets, never hard-code
λ real. 65+ code fixes, 249 commits since Mar 25
λ reviewer. DashScope qwen3.5-plus (timeout issues)
λ async. Daemon never blocks
λ safety. Main NEVER touched by auto-workflow
λ retry. Curl timeout → automatic retry
λ cl-block. cl-return-from requires cl-block in defun
λ review. Pre-merge code review with retry loop
λ researcher. Periodic analysis for target selection
λ case. Backend names must match exactly (lowercase)
λ paths. Use $HOME, not hardcoded directories
λ daemon. systemctl --user restart emacs (NOT pkill)
λ string-prefix. Replace regex with string-prefix-p for partial match
```