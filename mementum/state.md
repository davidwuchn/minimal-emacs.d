# Mementum State

> Last session: 2026-03-26 11:30

## Total Improvements: 45+ Real Code Fixes

| # | File | Fix |
|---|------|-----|
| 1 | gptel-auto-workflow-strategic.el | Added `(require 'json)` |
| 2 | gptel-ext-fsm-utils.el | Fixed `%d` → `%s` for float-time |
| 3 | gptel-ext-retry.el | Refactor trim-tool-results-for-retry |
| 4 | gptel-tools-code.el | Fix resource leak in byte-compile |
| 5 | gptel-benchmark-core.el | Add error handling to read-json |
| 6 | gptel-ext-retry.el | Pass retry-count as parameter |
| 7 | gptel-auto-workflow-strategic.el | Fix recursive file discovery |
| 8 | gptel-ext-fsm-utils.el | Fix FSM context validation |
| 9 | gptel-ext-context.el | Fix undefined function `estimate-tokens` |
| 10 | gptel-benchmark-core.el | Add defensive check for undefined variable |
| 11 | gptel-ext-retry.el | Remove redundant repair call |
| 12 | gptel-auto-workflow-strategic.el | Add missing `(require 'cl-lib)` |
| 13 | gptel-ext-backends.el | Curl timeout 300s → 600s |
| 14 | gptel-ext-context.el | Fix `cl-return` outside loop |
| 15 | gptel-tools-agent.el | Add `cl-block` for `gptel-auto-experiment-grade` |
| 16 | gptel-benchmark-instincts.el | Add `cl-block` for `commit-batch` |
| 17 | gptel-benchmark-memory.el | Add `cl-block` for `memory-create` |
| 18 | gptel-tools-agent.el | `block` → `cl-block` in `task-override` |
| 19 | gptel-ext-context-cache.el | Input validation in `estimate-text-tokens` |
| 20 | gptel-benchmark-core.el | Input validation in `summarize-results` |
| 21 | gptel-ext-context-cache.el | `cl-block` for `openrouter-fetch-context-window` |
| 22 | gptel-ext-backends.el | Backend name `Moonshot` → `moonshot` (case fix) |
| 23 | gptel-tools-agent.el | `cl-block` for `my/gptel--run-agent-tool` |
| 24 | gptel-benchmark-core.el | Consolidate duplicate maphash in analyze-patterns |
| 25 | gptel-ext-retry.el | Extract transient error patterns into constants |
| 26 | gptel-auto-workflow-strategic.el | Add input validation for nil dereference |
| 27 | gptel-ext-context-cache.el | `cl-block` for `openrouter-fetch-context-window` (re-fix) |
| 28 | gptel-ext-context-cache.el | Remove async fetch from context-window getter |
| 29 | gptel-benchmark-core.el | Consolidate duplicate maphash (workflow fix) |
| 30 | gptel-ext-retry.el | Extract message iteration into helper function |
| 31 | gptel-auto-workflow-strategic.el | Limit regex fallback targets to max-targets |
| 32 | scripts/*.sh | Use $HOME instead of hardcoded /Users/davidwu |
| 33 | gptel-ext-context-cache.el | Escape regex in `alist-partial-match` |
| 34 | gptel-ext-context-cache.el | Cache model-id to avoid redundant calls |
| 35 | gptel-ext-context-cache.el | Optimize `get-model-metadata` avoid redundant calls |
| 36 | gptel-tools-code.el | Fix byte-compile output capture race with sit-for |
| 37 | gptel-tools-agent.el | Prevent double-callback in `experiment-decide` |
| 38 | gptel-benchmark-core.el | Fix plist/alist detection in `to-json-format` |
| 39 | gptel-benchmark-core.el | Extract score extraction into helper function |

---

## λ Summary

```
λ subscriptions. DashScope (8) + moonshot (2)
λ parallel. macOS (daylight) + Pi5 (24/7 Linux)
λ dynamic. LLM selects targets, never hard-code
λ real. 45+ code fixes, not documentation
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
```