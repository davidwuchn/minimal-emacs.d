# Mementum State

> Last session: 2026-03-26 23:00

## Total Improvements: 85+ Real Code Fixes

246 commits since March 25, 2026.

### Recent Fixes (Last 25)

| # | File | Fix |
|---|------|-----|
| 85 | gptel-ext-context.el | Use buffer-size for accurate chars-after |
| 84 | gptel-ext-retry.el | Eliminate list conversion overhead |
| 83 | gptel-tools-agent.el | Temp file cleanup in deliver-subagent-result |
| 82 | gptel-tools-agent.el | Extract response normalization helper |
| 81 | gptel-tools-code.el | Symbol-name validation in find-usages |
| 80 | gptel-ext-context-cache.el | Eliminate redundant model-id computation |
| 79 | gptel-tools-agent.el | Unicode sanitization in log |
| 78 | gptel-tools-code.el | Fix LSP retry logic |
| 77 | gptel-tools-agent.el | Use setf for plist modification |
| 76 | gptel-ext-core.el | Extract char validation helper |
| 75 | gptel-ext-context-cache.el | Error handling for make-process |
| 74 | gptel-tools-agent.el | Code validation before benchmark |
| 73 | gptel-ext-context-cache.el | Revert broken cache change |
| 72 | gptel-tools-agent.el | Strengthen grading criteria |
| 71 | assistant/agents/reviewer.md | Switch to qwen3-coder-next |
| 70 | gptel-tools-code.el | Replace nreverse with reverse |
| 69 | gptel-auto-workflow-strategic.el | Path containment validation |
| 68 | gptel-ext-context.el | Eliminate duplicate token counting |
| 67 | eca-security.el | Fix temp directory path |
| 66 | gptel-ext-context-cache.el | Replace regex with string-prefix-p |
| 65 | gptel-auto-workflow-strategic.el | Extract validation logic into helper |
| 64 | gptel-auto-workflow-strategic.el | Validate-and-add-target returns nil |
| 63 | gptel-auto-workflow-strategic.el | Remove extra closing paren |
| 62 | gptel-benchmark-core.el | Fix destructive nreverse |
| 61 | gptel-ext-context-cache.el | Fix metadata cache inconsistency |

---

## λ Summary

```
λ subscriptions. DashScope (8) + moonshot (2)
λ parallel. macOS (daylight) + Pi5 (24/7 Linux)
λ dynamic. LLM selects targets, never hard-code
λ real. 85+ code fixes, 246 commits since Mar 25
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
λ buffer-size. Use buffer-size for accurate chars-after measurement
```