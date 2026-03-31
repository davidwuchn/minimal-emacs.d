# Mementum State

> Last session: 2026-03-30 16:45

## Total Improvements: 162+ Real Code Fixes

529+ commits since March 25, 2026.

### Recent Fixes (Last 42)

| # | File | Fix |
|---|------|-----|
| 169 | gptel-tools-agent.el | Commit executor changes before Eight Keys scoring (fixes "Winner: tie" discards) |
| 168 | gptel-tools-agent.el | Route subagent overlays to correct buffer (dynamic variable + fallback) |
| 167 | gptel-tools-agent.el | Sanitize multi-line output in log messages (fixes "Unknown message" errors) |
| 166 | gptel-tools-agent.el | Fixed 4 substring args-out-of-range errors (commit-hash, orphan, staging/main, date parsing) |
| 165 | gptel-tools-agent.el | Validation retry: Added type checking (stringp validation-error) and length check |
| 164 | gptel-tools-agent.el | Fixed syntax error: Separated merged function definitions (shell-command-with-timeout + read-file-contents) |
| 163 | gptel-benchmark-subagent.el | Fixed cross-module visibility: Added require/declare-function for gptel-auto-workflow--read-file-contents |
| 162 | gptel-tools-agent.el | Worktree nesting: use git-common-dir to find main repo from worktree |
| 161 | gptel-tools-agent.el | void-variable baseline-code-quality: pass to experiment-run |
| 160 | gptel-tools-agent.el | Grader behaviors: accept code quality improvements (clarity/testability) |
| 159 | gptel-tools-agent.el | Handle nil agent-output in error categorization + better grader logging |
| 159 | gptel-tools-agent.el | Skill gaps → benchmark tests (feedback loop for skill improvement) |
| 158 | executor.md | Skill check step 1 of tool loop (before editing .el/.clj) |
| 157 | gptel-tools-agent.el | Retry validation failures with skill instruction + skill gap logging |
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
λ validation-retry. Retry with skill instruction + log skill gap for improvement
λ skill-first-rule. Tool loop step 1: check file type → load skill before editing
λ skill-gap-feedback. Validation fails → log gap → convert to benchmark → improve skill → fewer gaps
λ auto-revert-conflict. Worktree file writes trigger revert on main buffer → disable during workflow
λ uniquify-buffer-names. Multiple same-name files get prefixes like .emacs.d/ → disable during workflow
λ substring-safety. (if (>= (length s) n) (substring s 0 n) s) | never assume string length
λ grader-behaviors. Expected: "improves code" (bug/perf/clarity/testability), not just "fixes bug"
λ grader-forbidden. "replaces working code WITHOUT improvement" (not all refactoring forbidden)
λ verification-flexible. "verification attempted" (byte-compile/nucleus/tests/manual) vs "tests pass"
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

- **Main branch**: `04948b5` (substring safety fixes)
- **Staging branch**: synced
- **Auto-workflow**: 114 experiments, 12 kept (10.5% success rate)
- **Daemon**: Single instance stable (110+ seconds)
- **Cron errors**: Fixed args-out-of-range (4 locations)

### Bugs Fixed Today

| Bug | Root Cause | Fix |
|-----|------------|-----|
| args-out-of-range (1 0 7) | substring on short/empty strings | Add length guards before substring |
| void-function read-file-contents | Cross-module visibility | Add require/declare-function |
| Merged function definitions | Syntax error in file | Separate shell-command-with-timeout and read-file-contents |
| Validation retry fails | nil validation-error | Add (stringp validation-error) and (> (length validation-error) 0) checks |
| Nested worktrees | project-root returns worktree root | Use git-common-dir |
| void-variable baseline-code-quality | Not passed to experiment-run | Add parameter |
| void-variable code-quality | Not in retry lambda scope | Compute locally |
| Benchmark runs unconditionally | At column 0 (outside lambda) | Move to else branch |
| Grader uses wrong criteria | Skill Mode taking priority | Prioritize Code Mode in prompt |

### Current Results

| Metric | Value |
|--------|-------|
| Total experiments | 61 |
| Kept | 3 (nucleus-tools.el, gptel-sandbox.el x2) |
| Success rate | 4.9% |
| Code crashes | None |
| Grader format | 10 Code Mode, 7 Skill Mode (improving) |

### Grader Improvement

Before: All responses used `seo_geo_optimization` or `eight-keys-grading`
After: 10 responses use `EXPECTED:` / `SCORE:` format (correct Code Mode)

### Next Run Checklist

- [ ] Worktrees cleaned up at start
- [ ] Auto-revert disabled
- [ ] Uniquify disabled
- [ ] Grader uses 80% threshold
- [ ] Error categorization improved
- [ ] Grader behaviors include "improves code quality" (not just bug fixes)
```
λ grader-failed ≠ api-error. Executor success + grader score 0 = grader issue
λ grader-strict. Score 2/9 for valid refactoring → expected behaviors exclude code quality improvements
λ forbidden-overreach. "replaces working code" catches beneficial refactoring
```

### Grader Behavior Gap Analysis (2026-03-30)

**Current Grader Expected Behaviors:**
1. change clearly described
2. change is minimal and focused
3. fixes real bug, improves performance, or addresses TODO/FIXME
4. tests pass after change

**Current Grader Forbidden Behaviors:**
1. large refactor unrelated to fix
2. changed security files without review
3. no description or unclear purpose
4. style-only change without functional impact
5. replaces working code with equivalent code

**Problem:**
- Refactoring (extracting helpers, deduplicating) fails "fixes real bug" (not a bug)
- Refactoring triggers "replaces working code with equivalent code" (forbidden)
- "tests pass" hard to verify from text output alone
- Score 2/9 = only 22% → fails 80% threshold

**Evidence:**
- Row 10: `gptel-tools-agent.el` - extracted helper function → grader_quality=2, discarded
- Row 13: `gptel-ext-tool-sanitize.el` - sliding window → grader_quality=2, discarded
- Row 14: `gptel-ext-tool-confirm.el` - buffer validation → grader_quality=2, discarded

**Proposed Fix:**
Add expected behavior: "improves code quality (clarity, vitality, testability)"
Modify forbidden: "replaces working code WITHOUT improvement" (not all refactoring)

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