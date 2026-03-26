# Mementum State

> Last session: 2026-03-26 23:30

## Total Improvements: 88+ Real Code Fixes

252 commits since March 25, 2026.

### Recent Fixes (Last 25)

| # | File | Fix |
|---|------|-----|
| 88 | gptel-auto-workflow-strategic.el | Extract target parsing helpers |
| 87 | gptel-workflow-benchmark.el | Fix P1 phase detection |
| 86 | gptel-ext-context.el | Use buffer-size for accurate chars-after |
| 85 | gptel-ext-retry.el | Eliminate list conversion overhead |
| 84 | gptel-tools-agent.el | Temp file cleanup in deliver-subagent-result |
| 83 | gptel-tools-agent.el | Extract response normalization helper |
| 82 | gptel-tools-code.el | Symbol-name validation in find-usages |
| 81 | gptel-ext-context-cache.el | Eliminate redundant model-id computation |
| 80 | gptel-tools-agent.el | Unicode sanitization in log |
| 79 | gptel-tools-code.el | Fix LSP retry logic |
| 78 | gptel-tools-agent.el | Use setf for plist modification |
| 77 | gptel-ext-core.el | Extract char validation helper |
| 76 | gptel-ext-context-cache.el | Error handling for make-process |
| 75 | gptel-tools-agent.el | Code validation before benchmark |
| 74 | gptel-ext-context-cache.el | Revert broken cache change |
| 73 | gptel-tools-agent.el | Strengthen grading criteria |
| 72 | assistant/agents/reviewer.md | Switch to qwen3-coder-next |
| 71 | gptel-tools-code.el | Replace nreverse with reverse |
| 70 | gptel-auto-workflow-strategic.el | Path containment validation |
| 69 | gptel-ext-context.el | Eliminate duplicate token counting |
| 68 | eca-security.el | Fix temp directory path |
| 67 | gptel-ext-context-cache.el | Replace regex with string-prefix-p |
| 66 | gptel-auto-workflow-strategic.el | Extract validation logic into helper |
| 65 | gptel-auto-workflow-strategic.el | Validate-and-add-target returns nil |
| 64 | gptel-auto-workflow-strategic.el | Remove extra closing paren |

---

## λ Summary

```
λ subscriptions. DashScope (8) + moonshot (2)
λ parallel. macOS (daylight) + Pi5 (24/7 Linux)
λ dynamic. LLM selects targets, never hard-code
λ real. 88+ code fixes, 252 commits since Mar 25
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