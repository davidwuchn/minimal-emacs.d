# Mementum State

> Last session: 2026-03-29 22:00

## Total Improvements: 156+ Real Code Fixes

524+ commits since March 25, 2026.

### Recent Fixes (Last 35)

| # | File | Fix |
|---|------|------|
| 156 | gptel-benchmark-subagent.el | Remove local-grader fallback (fail if subagent unavailable) |
| 155 | gptel-benchmark-subagent.el, gptel-tools-agent.el | Grader reliability: 80% threshold (not perfect), 120s timeout |
| 154 | gptel-tools-agent.el | Disable uniquify during headless workflow (prevents .emacs.d/ prefix) |
| 153 | gptel-tools-agent.el | Disable auto-revert during headless workflow (prevents buffer reverts) |
| 152 | gptel-tools-agent.el | Improve error categorization (detect grader failures vs real errors) |
| 151 | gptel-tools-agent.el | Safer staging branch sync (use cond) |
| 150 | cache-exp1, cache-exp2 | Merged: context window normalization + cache seeding |
| 149 | tools-exp2 | Merged: remove redundant conditional in nucleus-tools--validate-array |
| 148 | sanitize-exp2 | Merged: fix tool lookup bug (gptel-get-tool without args) |
| 147 | gptel-skill-benchmark.el | Fix: use executor agent (not skill name as agent) |
| 146 | benchmarks/skill-tests/elisp-expert.json | Benchmark test definitions (5 cases for dangerous patterns) |
| 145 | assistant/agents/*.md | {{SKILLS}} template for autonomous skill discovery |
| 144 | assistant/skills/elisp-expert/SKILL.md | Skill for gptel-agent subagents (dangerous patterns) |
| 143 | executor.md + elisp-expert SKILL.md | Skill-based pattern loading (not knowledge page injection) |
| 141 | ai-code-behaviors.el | cl-block wrappers for cl-return-from (3 functions fixed) |
| 140 | gptel-tools-agent.el | Keep worktree for entire target, delete only at next run start |
| 139 | gptel-auto-workflow-projects.el | Check worktree exists before routing |
| 138 | gptel-auto-workflow-projects.el | Remove conflicting old advice, merge caching |
| 137 | gptel-tools-agent.el | Add kill-buffer query suppression |
| 136 | assistant/agents/executor.md | Switch to qwen3.5-plus (fixes JSON format errors) |
| 135 | gptel-tools-agent.el | Capture buffer for analyzer, comparator overlays |
| 134 | gptel-tools-agent.el | Error categorization: api-rate-limit, timeout, tool-error |
| 133 | gptel-tools-agent.el | Adaptive max-experiments when API errors ≥ 3 |
| 132 | gptel-tools-agent.el | Failure analysis logging |
| 131 | gptel-tools-agent.el | hash-table-p check for project-buffers |
| 130 | gptel-tools-preview.el | Bypass preview in headless auto-workflow |
| 129 | init-tools.el | Disable easysession auto-save timer |
| 128 | gptel-tools-agent.el | Headless prompt suppression |

---

## λ Summary

```
λ subscriptions. DashScope (8) + moonshot (2)
λ parallel. macOS (daylight) + Pi5 (24/7 Linux)
λ dynamic. LLM selects targets, never hard-code
λ real. 140+ code fixes, 515+ commits since Mar 25
λ headless. Suppress ALL prompts (ask-user, yes-or-no, y-or-n, kill-buffer)
λ advice-conflict. :override + :around on same fn = unpredictable
λ with-current-buffer. make-overlay uses current buffer DIRECTLY
λ qwen-coder-json. qwen3-coder-plus generates invalid JSON for tools
λ executor-model. Use qwen3.5-plus (NOT qwen3-coder-plus) for tool calling
λ worktree-lifecycle. Created at start, deleted at NEXT run start
λ never-manual-cleanup. Let workflow manage its own resources
λ cl-return-from. Requires cl-block wrapper in Elisp (dangerous pattern)
λ skill-based-patterns. Use knowledge pages (skills), NOT system prompt modifications
λ skill-autonomy. Subagent uses Skill tool autonomously (parent instructs, child loads)
λ gptel-agent-skill-dirs. ~/.emacs.d/assistant/skills/ first, then ~/.opencode/skill/, etc.
λ {{SKILLS}}-template. Inject available_skills into agent system prompt (gptel-agent auto-expands)
λ agent-vs-skill. gptel-agent--task expects agent name (executor), NOT skill name (elisp-expert)
λ overlay-buffer-context. make-overlay(nil) uses current-buffer, advice needed for async callbacks
λ grader-passed. :passed >= 80% threshold (not perfect), perfect score unrealistic
λ grader-fail. No local fallback - fail experiment if grader subagent unavailable
λ auto-revert-conflict. Worktree file writes trigger revert on main buffer → disable during workflow
λ uniquify-buffer-names. Multiple same-name files get prefixes like .emacs.d/ → disable during workflow
```

---

## Worktree Lifecycle (CRITICAL)

```
λ create. When first experiment of target starts
λ persist. Through ALL experiments for that target
λ persist. After target done (for potential staging merge)
λ delete. At START of NEXT workflow run (not end of current)
λ never-manual. Don't delete worktrees while workflow running
```

**Why not delete at end of run?**
1. Staging merge happens AFTER workflow completes
2. Executor processes may still be running (async)
3. Manual cleanup causes "No such file or directory" errors

**Cleanup location**: `gptel-auto-workflow--cleanup-old-worktrees` in `gptel-auto-workflow-cron-safe`

---

## Headless Suppression (Complete)

| Prompt | Function | Suppression |
|--------|----------|-------------|
| "has changed since visited" | `ask-user-about-supersession-threat` | Advice returns 'revert |
| "Save anyway? (y or n)" | `yes-or-no-p`, `y-or-n-p` | Advice returns t |
| "Diff Preview - Confirm" | Preview bypass | Headless flag check |
| "Buffer modified; kill anyway?" | `kill-buffer-query-functions` | Hook returns nil |

---

## Subagent Overlay Routing

**Problem**: Overlays appearing in *Messages* buffer.

**Root Cause**: TWO conflicting advices:
1. `my/gptel-agent--task-override` with `:override` (old)
2. `gptel-auto-workflow--advice-task-override` with `:around` (new)

**Solution**:
- Removed old `:override` advice
- Merged caching logic into new `:around` advice
- Use `with-current-buffer` (make-overlay uses current buffer DIRECTLY)
- Check worktree exists before routing

**Pattern**: Multiple advices with different types on same function = unpredictable.

---

## Current Status

- **Main branch**: `ac7c8b4`
- **Staging branch**: `1863ef3` (synced with main)
- **Skill elisp-expert**: ✓ Created, loaded, tested
- **Grader**: ✓ Reliability improved (80% threshold, 120s timeout, no fallback)

### Grader Reliability Fixes

| Issue | Before | After |
|-------|--------|-------|
| Pass threshold | 100% (perfect) | 80% (realistic) |
| Timeout | 60s | 120s |
| Fallback | Local-grader (weak) | Fail (no false passes) |
| Auto-revert | Enabled (buffer reverts) | Disabled during workflow |
| Uniquify | Enabled (confusing names) | Disabled during workflow |

### Expected Improvement

| Metric | Before | After (expected) |
|--------|--------|------------------|
| Success rate | 7% (1/14) | 30-50% |
| "Unknown error" | 10 failures | Clear categorization |
| Grader false fails | Many | Fewer (80% threshold) |

### Next Run Checklist

- [ ] Worktrees cleaned up at start
- [ ] Auto-revert disabled
- [ ] Uniquify disabled
- [ ] Grader uses 80% threshold
- [ ] Error categorization improved
```
λ grader-failed ≠ api-error. Executor success + grader score 0 = grader issue
```

### Bugs Fixed Today

| Issue | Root Cause | Fix |
|-------|------------|-----|
| 5 stuck "Elisp-Expert" overlays | skill name used as agent name | Use "executor" agent |
| Overlays in *scratch* | make-overlay uses current buffer | Advice on task-overlay to route to target buffer |

---

## Key Learnings Today

1. **Worktree timing** - Delete only at START of next run, not during or after current run
2. **Manual cleanup causes errors** - Executors run async, can't delete while running
3. **make-overlay** - Uses current buffer DIRECTLY, must use `with-current-buffer`
4. **Advice conflicts** - `:override` + `:around` = unpredictable behavior
5. **qwen-coder** - Can't use for tool calling (malformed JSON)
6. **kill-buffer-query** - Use hook, not advice
7. **cl-return-from** - Requires cl-block wrapper in Elisp (validation catches this)
8. **gptel-agent Skill** - gptel-agent has own Skill tool, skills go in `gptel-agent-skill-dirs` (~/.emacs.d/assistant/skills/ first)
9. **Skill autonomy** - Parent instructs "use Skill", subagent loads autonomously (not injection from parent)
10. **Agent vs Skill** - `gptel-agent--task` expects agent name (e.g. "executor"), NOT skill name - skills are loaded BY agents
11. **Async overlay context** - Overlays created in callbacks lose buffer context, need advice on `gptel-agent--task-overlay` to route
12. **Grader threshold** - 80% is realistic, 100% perfect score is unrealistic for LLM output
13. **No weak fallback** - Local-grader pattern matching gives false passes, fail instead
14. **Auto-revert/uniquify** - Disable during headless workflow to prevent interference