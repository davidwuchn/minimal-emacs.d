# Mementum State

> Last session: 2026-03-26 13:00

## Total Improvements: 60+ Real Code Fixes

152+ commits with fixes since March 25, 2026.

### Recent Fixes (Last 20)

| # | File | Fix |
|---|------|-----|
| 60 | gptel-ext-context-cache.el | Replace regex with string-prefix-p |
| 59 | gptel-auto-workflow-strategic.el | Extract validation logic into helper |
| 58 | gptel-auto-workflow-strategic.el | Validate-and-add-target returns nil |
| 57 | gptel-auto-workflow-strategic.el | Remove extra closing paren |
| 56 | gptel-benchmark-core.el | Fix destructive nreverse |
| 55 | gptel-ext-context-cache.el | Fix metadata cache inconsistency |
| 54 | gptel-ext-context-cache.el | Use full metadata cache |
| 53 | gptel-benchmark-core.el | Fix inconsistent indentation |
| 52 | gptel-tools-code.el | Extract tree-sitter validation helper |
| 51 | gptel-auto-workflow-strategic.el | Fix JSON parsing bug |
| 50 | gptel-auto-workflow-strategic.el | Fix regex fallback for subdirs |
| 49 | gptel-ext-retry.el | Handle list content in strip-images |
| 48 | gptel-benchmark-core.el | Fix nreverse in two functions |
| 47 | gptel-benchmark-core.el | Fix destructive nreverse in trend |
| 46 | gptel-ext-context.el | Fix preview/replace branch logic |
| 45 | gptel-ext-context.el | Refactor auto-compact-needed-p |
| 44 | gptel-ext-context-cache.el | Extract cache-or-alist-lookup helper |
| 43 | gptel-ext-context.el | Optimize token calculation |
| 42 | gptel-agent-loop.el | Add fboundp safety check |
| 41 | gptel-agent-loop.el | Extract overlay cleanup into helper |

---

## λ Summary

```
λ subscriptions. DashScope (8) + moonshot (2)
λ parallel. macOS (daylight) + Pi5 (24/7 Linux)
λ dynamic. LLM selects targets, never hard-code
λ real. 60+ code fixes, 152+ commits since Mar 25
λ reviewer. Switched to DashScope (faster, more reliable)
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