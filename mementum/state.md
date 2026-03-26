# Mementum State

> Last session: 2026-03-26 17:30

## Total Improvements: 70+ Real Code Fixes

258 commits since March 25, 2026.

### Recent Fixes (Last 30)

| # | File | Fix |
|---|------|-----|
| 70 | assistant/agents/reviewer.md | Switch to qwen3-coder-next (no thinking issues) |
| 69 | gptel-tools-agent.el | Strengthen grading criteria |
| 70 | gptel-tools-agent.el | Fix timeout auto-pass |
| 68 | gptel-tools-code.el | Replace nreverse with reverse |
| 67 | gptel-auto-workflow-strategic.el | Path containment validation |
| 66 | gptel-ext-context.el | Eliminate duplicate token counting |
| 65 | eca-security.el | Fix temp directory path |
| 64 | gptel-ext-context-cache.el | Replace regex with string-prefix-p |
| 63 | gptel-auto-workflow-strategic.el | Extract validation logic into helper |
| 62 | gptel-auto-workflow-strategic.el | Validate-and-add-target returns nil |
| 61 | gptel-auto-workflow-strategic.el | Remove extra closing paren |
| 60 | gptel-benchmark-core.el | Fix destructive nreverse |
| 59 | gptel-ext-context-cache.el | Fix metadata cache inconsistency |
| 58 | gptel-ext-context-cache.el | Use full metadata cache |
| 57 | gptel-benchmark-core.el | Fix inconsistent indentation |
| 56 | gptel-tools-code.el | Extract tree-sitter validation helper |
| 55 | gptel-auto-workflow-strategic.el | Fix JSON parsing bug |
| 54 | gptel-auto-workflow-strategic.el | Fix regex fallback for subdirs |
| 53 | gptel-ext-retry.el | Handle list content in strip-images |
| 52 | gptel-benchmark-core.el | Fix nreverse in two functions |
| 51 | gptel-benchmark-core.el | Fix destructive nreverse in trend |
| 50 | gptel-ext-context.el | Fix preview/replace branch logic |
| 49 | gptel-ext-context.el | Refactor auto-compact-needed-p |
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
λ real. 70+ code fixes, 258 commits since Mar 25
λ reviewer. qwen3-coder-next on DashScope (no thinking mode)
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