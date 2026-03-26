# Mementum State

> Last session: 2026-03-26 20:30

## Total Improvements: 75+ Real Code Fixes

270 commits since March 25, 2026.

### Recent Fixes (Last 20)

| # | File | Fix |
|---|------|-----|
| 75 | gptel-ext-core.el | Extract char validation helper |
| 74 | gptel-ext-context-cache.el | Error handling for make-process |
| 73 | gptel-tools-agent.el | Code validation before benchmark |
| 72 | gptel-ext-context-cache.el | Revert broken cache change |
| 71 | gptel-tools-agent.el | Strengthen grading criteria |
| 70 | assistant/agents/reviewer.md | Switch to qwen3-coder-next |
| 69 | gptel-tools-code.el | Replace nreverse with reverse |
| 68 | gptel-auto-workflow-strategic.el | Path containment validation |
| 67 | gptel-ext-context.el | Eliminate duplicate token counting |
| 66 | eca-security.el | Fix temp directory path |
| 65 | gptel-ext-context-cache.el | Replace regex with string-prefix-p |
| 64 | gptel-auto-workflow-strategic.el | Extract validation logic into helper |
| 63 | gptel-auto-workflow-strategic.el | Validate-and-add-target returns nil |
| 62 | gptel-auto-workflow-strategic.el | Remove extra closing paren |
| 61 | gptel-benchmark-core.el | Fix destructive nreverse |
| 60 | gptel-ext-context-cache.el | Fix metadata cache inconsistency |
| 59 | gptel-ext-context-cache.el | Use full metadata cache |
| 58 | gptel-benchmark-core.el | Fix inconsistent indentation |
| 57 | gptel-tools-code.el | Extract tree-sitter validation helper |
| 56 | gptel-auto-workflow-strategic.el | Fix JSON parsing bug |
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
λ real. 75+ code fixes, 270 commits since Mar 25
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