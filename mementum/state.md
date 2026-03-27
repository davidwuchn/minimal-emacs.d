# Mementum State

> Last session: 2026-03-27 15:05

## Total Improvements: 100+ Real Code Fixes

351 commits since March 25, 2026.

### Recent Fixes (Last 25)

| # | File | Fix |
|---|------|-----|
| 100 | gptel-ext-context-cache.el | Fix redundant buffer-file-name call |
| 99 | gptel-tools-code.el | Fix LSP backend lookup in find-usages |
| 98 | gptel-ext-tool-sanitize.el | Fix gptel-get-tool called without arguments |
| 97 | gptel-tools-agent.el | Hostname-based worktree cleanup |
| 96 | gptel-tools-agent.el | Simplify: remove ALL old worktrees |
| 95 | scripts/setup-packages.sh | Add --force and --clean options |
| 94 | post-init.el | Add server-start for GUI Emacs |
| 93 | gptel-tools-agent.el | Simplify headless detection (OS type) |
| 92 | gptel-tools-agent.el | Auto-detect quiet hours based on OS |
| 91 | gptel-tools-agent.el | Default inactivity timeout 30 min |
| 90 | cron.d/auto-workflow* | Use $HOME instead of $LOGDIR |
| 89 | ai-code | Cons cell validation in cache-get |
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

---

## λ Summary

```
λ subscriptions. DashScope (8) + moonshot (2)
λ parallel. macOS (daylight) + Pi5 (24/7 Linux)
λ dynamic. LLM selects targets, never hard-code
λ real. 100+ code fixes, 351 commits since Mar 25
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
λ cron. Use $HOME directly, not $LOGDIR variable
λ headless. Detect by OS type: macOS=user, Linux=headless
λ quiet-hours. Auto-detect: macOS=9-17, Linux=24/7
λ server-start. GUI Emacs acts as server for cron jobs
λ worktree-cleanup. Hostname-based, clean ALL at run start
λ experiment-suffix. Derived from (system-name) for multi-machine
```

---

## Current Status

- **Main branch**: `31e70ca`
- **Workflow**: Running (5 targets)
- **Worktrees**: 5 active (cache, change, code, sanitize, strategic)
- **Next scheduled**: 15:00 (in progress)
- **Cron**: 4 jobs installed, executing on schedule

---

## ai-code-behaviors + agent-shell Integration

**Completed**: 2026-03-27

| Feature | Status |
|---------|--------|
| Decorator handles alist prompt format | ✅ |
| `@preset` → behavior injection | ✅ |
| `#hashtag` completion | ✅ |
| Hash table for `C-c P` inspection | ✅ |
| Mode-line indicator | ✅ |

**Key files**:
- `packages/ai-code/ai-code-behaviors.el:3290` - `ai-code-agent-shell-request-decorator`
- `lisp/init-ai.el:99-135` - agent-shell configuration