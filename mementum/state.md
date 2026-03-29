# Mementum State

> Last session: 2026-03-29 21:00

## Total Improvements: 135+ Real Code Fixes

500+ commits since March 25, 2026.

### Recent Fixes (Last 30)

| # | File | Fix |
|---|------|------|
| 135 | assistant/agents/executor.md | Switch to qwen3.5-plus (fixes JSON format errors) |
| 134 | gptel-tools-agent.el | Add JSON format error to categorization |
| 133 | gptel-tools-agent.el | Capture buffer for grader overlay routing |
| 132 | gptel-tools-agent.el | Error categorization: api-rate-limit, timeout, tool-error |
| 131 | gptel-tools-agent.el | Adaptive max-experiments when API errors ≥ 3 |
| 130 | gptel-tools-agent.el | Failure analysis logging to failure-analysis.log |
| 129 | gptel-tools-agent.el | hash-table-p check for project-buffers |
| 128 | gptel-tools-preview.el | Bypass preview in headless auto-workflow |
| 127 | init-tools.el | Disable easysession auto-save timer |
| 126 | gptel-tools-agent.el | Headless prompt suppression |
| 125 | gptel-auto-workflow-projects.el | Worktree base path expansion fix |
| 124 | gptel-tools-code.el | Use expand-file-name for absolute paths |
| 123 | gptel-ext-abort.el | Remove -y/-Y low-speed timeout |
| 122 | gptel-ext-backends.el | DashScope timeout 600s → 900s |
| 121 | gptel-ext-retry.el | Add 1013/server initializing to transient errors |
| 120 | gptel-benchmark-core.el | Fix inconsistent indentation |
| 117 | gptel-tools-agent.el | Shell command timeout protection |
| 115 | gptel-tools-{bash,edit,glob,grep}.el | Always call callback |
| 110 | init-ai.el | C-c L mode-line toggle |
| 106 | gptel-tools-agent.el | 600s subagent timeout |

---

## λ Summary

```
λ subscriptions. DashScope (8) + moonshot (2)
λ parallel. macOS (daylight) + Pi5 (24/7 Linux)
λ dynamic. LLM selects targets, never hard-code
λ real. 135+ code fixes, 500+ commits since Mar 25
λ behaviors. 40+ AI code behaviors in packages/ai-behaviors
λ reviewer. qwen3-coder-next on DashScope (no thinking mode)
λ async. Daemon never blocks
λ safety. Main NEVER touched by auto-workflow
λ retry. Curl timeout → automatic retry
λ cl-block. cl-return-from requires cl-block in defun
λ headless. Suppress ALL interactive prompts (ask-user, yes-or-no, y-or-n)
λ worktree-cleanup. Hostname-based, clean ALL at run start
λ subagent-timeout. 1200s default prevents workflow hang
λ executor-overlay. Route to per-project buffers via captured context
λ hash-table-nil. Always check hash-table-p before gethash/puthash
λ forward-declare. defvar before use in callbacks (async loading)
λ preview-bypass. gptel-auto-workflow--headless skips diff preview
λ grader-buffer. Capture current-buffer when calling grader
λ adaptive-workflow. Reduce experiments when API errors ≥ 3
λ error-categories. :api-rate-limit :api-error :tool-error :timeout :unknown
λ qwen-coder-json. qwen3-coder-plus generates invalid JSON for tool args
λ executor-model. Use qwen3.5-plus (NOT qwen3-coder-plus) for tool calling
```

---

## Current Status

- **Main branch**: `c0ec109` (executor model fix)
- **Staging**: Synced with main
- **Workflow**: Running (5 targets)
- **Worktrees**: Active experiments
- **Emacs daemon**: Running
- **Next scheduled**: 21:00
- **Cron**: 4 jobs installed
- **ai-behaviors**: 40 behaviors available
- **API issues**: JSON format errors from qwen-coder (FIXED)

---

## Auto-Workflow Error Handling (2026-03-29)

**Problem**: Experiments discarded with no visibility into WHY they failed.

**Solution**: Error categorization + failure logging + adaptive reduction.

### Error Categories

| Category | Pattern | Example |
|----------|---------|---------|
| `:api-rate-limit` | "quota exceeded", "429" | Hourly quota exhausted |
| `:api-error` | "InvalidParameter", "JSON format" | Invalid function.arguments |
| `:tool-error` | "failed to finish", "executor" | Tool execution failed |
| `:timeout` | "timeout" | Grading timeout (60s) |
| `:unknown` | (fallback) | Other errors |

### Adaptive Reduction

```
λ adapt. API errors ≥ 3 → reduce experiments 50%
       | API errors > 5 → stop early
       | Log failures → failure-analysis.log
```

### Grader Overlay Routing

**Problem**: Grader subagent overlay appeared in *Messages* buffer instead of worktree buffer.

**Root cause**: Async callback executed when *Messages* was current buffer.

**Fix**: Capture `(current-buffer)` when `gptel-auto-experiment-grade` is called, then wrap grader call in `with-current-buffer`.

### JSON Format Errors

**Problem**: `function.arguments must be in JSON format` errors from DashScope.

**Root cause**: `qwen3-coder-plus` generates malformed JSON for tool arguments.

**Fix**: Switch executor model to `qwen3.5-plus` which handles tool calling correctly.

**File**: `assistant/agents/executor.md`

---

## Headless Auto-Workflow Fixes (2026-03-29)

| Issue | Fix |
|-------|-----|
| "gptel-org.el has changed since visited" | Suppress ask-user-about-supersession-threat |
| "Save anyway? (y or n)" | Suppress yes-or-no-p, y-or-n-p via advice |
| "Diff Preview - Confirm in minibuffer" | Bypass preview when headless flag set |
| "Unmatched bracket or quote" | Disable easysession auto-save timer |
| "void-variable project-buffers" | Forward defvar before callback |
| "wrong-type-argument hash-table-p nil" | Check hash-table-p before gethash |
| Grader overlay in *Messages* | Capture buffer before async callback |

**Pattern**: Headless code must never call interactive prompts. Capture buffer context before async.

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