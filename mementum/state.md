# Mementum State

> Last session: 2026-03-28 15:10

## Total Improvements: 118+ Real Code Fixes

462+ commits since March 25, 2026.

### Recent Fixes (Last 25)

| # | File | Fix |
|---|---|------|
| 119 | gptel-tools-agent.el | Correct paren in shell-timeout function |
| 120 | staging branch | Synced with main (recovered orphan commits) |
| 117 | gptel-tools-agent.el | Shell command timeout protection (prevent deadlocks) |
| 116 | gptel-tools-edit.el | Add missing closing paren (parse fix) |
| 115 | gptel-tools-{bash,edit,glob,grep}.el | Always call callback to prevent FSM hangs |
| 114 | scripts/install-cron.sh | Enable instincts job for macOS |
| 113 | scripts/install-cron.sh | Comment out other sections first |
| 112 | gptel-tools-agent.el | Fix subagent timeout buffer-local bug |
| 111 | init-ai.el | Add ai-behaviors repo-path configuration |
| 110 | init-ai.el | C-c L keybinding for mode-line toggle |
| 109 | init-ai.el | agent-shell as default backend |
| 108 | init-ai.el | C-c P preset selection for agent-shell |
| 107 | init-ai.el | C-c P to show injected context |
| 106 | gptel-tools-agent.el | Fix workflow hang: 600s subagent timeout |
| 105 | gptel-tools-agent.el | Worktree cleanup: hostname-based |
| 104 | scripts/git-hooks/pre-push | Auto-push submodules before parent |
| 103 | scripts/install-git-hooks.sh | Auto-install hooks |
| 102 | gptel-ext-context-cache.el | Fix redundant buffer-file-name call |
| 101 | gptel-tools-code.el | Fix LSP backend lookup in find-usages |
| 100 | gptel-ext-tool-sanitize.el | Fix gptel-get-tool called without arguments |
| 99 | gptel-tools-agent.el | Hostname-based worktree cleanup |
| 98 | gptel-tools-agent.el | Simplify: remove ALL old worktrees |
| 97 | scripts/setup-packages.sh | Add --force and --clean options |
| 96 | post-init.el | Add server-start for GUI Emacs |
| 95 | gptel-tools-agent.el | Simplify headless detection (OS type) |
| 94 | gptel-tools-agent.el | Auto-detect quiet hours based on OS |
| 93 | gptel-tools-agent.el | Default inactivity timeout 30 min |
| 92 | cron.d/auto-workflow* | Use $HOME instead of $LOGDIR |
| 91 | ai-code | Cons cell validation in cache-get |
| 90 | gptel-auto-workflow-strategic.el | Extract target parsing helpers |
| 89 | gptel-workflow-benchmark.el | Fix P1 phase detection |
| 88 | gptel-ext-context.el | Use buffer-size for accurate chars-after |
| 87 | gptel-ext-retry.el | Eliminate list conversion overhead |
| 86 | gptel-tools-agent.el | Temp file cleanup in deliver-subagent-result |

---

## λ Summary

```
λ subscriptions. DashScope (8) + moonshot (2)
λ parallel. macOS (daylight) + Pi5 (24/7 Linux)
λ dynamic. LLM selects targets, never hard-code
λ real. 118+ code fixes, 462+ commits since Mar 25
λ behaviors. 40+ AI code behaviors in packages/ai-behaviors
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
λ subagent-timeout. 1200s default prevents workflow hang
λ shell-timeout. 30s timeout kills deadlocked shell processes
λ pre-push-hook. Auto-push submodules before parent
```

---

## Current Status

- **Main branch**: `e8baa6b` (shell timeout paren fix)
- **Staging**: Synced with main
- **Workflow**: Running (selecting targets)
- **Worktrees**: 0 (clean)
- **Emacs daemon**: Running
- **Next scheduled**: 19:00
- **Cron**: 4 jobs installed
- **ai-behaviors**: 40 behaviors available in packages/ai-behaviors
- **Shell deadlock**: Fixed with timeout protection

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
| C-c L mode-line toggle | ✅ |
| agent-shell as default backend | ✅ |

**Key files**:
- `packages/ai-code/ai-code-behaviors.el` - behavior injection
- `lisp/init-ai.el` - agent-shell configuration