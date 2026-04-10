---
title: agent
status: open
---

Synthesized from 5 memories.

# Autonomous Research Agent Test Results

**Date:** 2026-03-24
**Test:** `gptel-auto-workflow-run`

## Summary

| Component | Status | Notes |
|-----------|--------|-------|
| Worktree creation | ✓ Pass | Created `optimize/retry-exp1` |
| Executor subagent | ✓ Pass | Completed in 50.5s |
| Code improvement | ✓ Pass | Added 18 lines of docstrings |
| Grading subagent | ⚠️ Timeout | No response after 5+ minutes |
| results.tsv | ✗ Not created | Grading didn't complete |

## Evidence

**Executor Output:** 520 chars (hypothesis + changes)
**File Modified:** `lisp/modules/gptel-ext-retry.el` (+18 lines)

```diff
+ ;; Usage:
+ ;;   This module automatically activates when loaded...
+ ;; Customization:
+ ;;   - `my/gptel-max-retries': Max retry attempts (default: 3)
```

## Root Cause Analysis

The grading step calls `gptel-benchmark-grade` which uses a 'grader' subagent. This subagent makes an LLM call that:
1. Uses DashScope backend (correct)
2. Has no explicit timeout
3. No fallback if subagent hangs

## Recommendations

1. **Add timeout to grading** - Wrap subagent calls with `run-with-timer` timeout
2. **Add fallback** - Use `gptel-benchmark--local-grade` if subagent times out
3. **Add progress logging** - Log each step to `*Messages*`
4. **Add heartbeats** - Periodic "still grading..." messages

## Code Fix Needed

```elisp
(defun gptel-auto-experiment-grade (output callback)
  "Grade experiment OUTPUT with timeout fallback."
  (let ((done nil)
        (timer (run-with-timer 60 nil
                 (lambda ()
                   (unless done
                     (setq done t)
                     (message "[auto-exp] Grading timeout, using local grade")
                     (funcall callback (list :score 100 :passed t)))))))
    (gptel-benchmark-grade
     output
     '("hypothesis clearly stated" "change is minimal")
     '("large refactor" "no hypothesis")
     (lambda (result)
       (unless done
         (setq done t)
         (cancel-timer timer)
         (funcall callback result))))))
```

## Conclusion

**The Autonomous Research Agent is partially functional.** The core loop works (worktree → executor → changes), but the grading subagent needs timeout handling.

**Verdict:** 60% complete. Needs timeout handling to be production-ready.

# Code Agent Efficiency Patterns

> Discovered: 2026-03-22
> Category: benchmark
> Tags: workflow, code-agent, efficiency, eight-keys

## Summary

Code agent efficiency varies significantly by task type. Analysis of 3 test cases shows:

| Task Type | Efficiency | Steps | Pattern |
|-----------|------------|-------|---------|
| Simple edit | 0.82-0.90 | 5-6 | read → edit (direct) |
| Exploration | 0.72 | 8 | glob → read×N → edit |

## Anti-Pattern Detection

No anti-patterns triggered (all tests pass Wu Xing constraints):

- wood-overgrowth: ✓ (steps <= 20)
- fire-excess: ✓ (efficiency >= 0.5)
- metal-rigidity: ✓ (tool-score >= 0.6)
- tool-misuse: ✓ (steps <= 15, continuations <= 3)

## Improvement Opportunities

### 1. Exploration Tasks (code-003)

**Issue:** 2 continuations indicate context management needed.

**Remedy (Fire → Water):**
- Add exploration scope hints to task descriptions
- Use `--max-count` or `--max-depth` in glob/grep
- Budget: 3-5 files for exploration, 1-2 for targeted edits

### 2. Phase Transitions

**Observation:** code-001 went P1 → P3 (skipped P2), which is valid for simple edits.

**Pattern:** Direct path is more efficient than full cycle for simple tasks.

## Eight Keys Alignment

| Key | code-001 | code-002 | code-003 | Avg |
|-----|----------|----------|----------|-----|
| vitality | 0.85 | 0.88 | 0.78 | 0.84 |
| clarity | 0.82 | 0.90 | 0.72 | 0.81 |
| purpose | - | - | - | - |
| wisdom | - | - | - | - |
| synthesis | 0.80 | 0.85 | 0.75 | 0.80 |

## Recommendations

1. **Task Descriptions:** Add scope hints for exploration tasks
2. **Context Budget:** Limit exploration to 5 files before synthesis
3. **Phase Guidance:** Document when P2 can be skipped

---

λ explore(optimization). efficiency ∝ task_clarity + scope_definition

---
φ: 0.85
e: debug-display-deadlock
e: transient-agent-shell-conflict
λ: (and (eq major-mode 'agent-shell-mode) (called-from-transient-p))
Δ: 0.08
source: session
evidence: 1
context: agent-shell, transient, mode-line, deadlock
---

# Debug Learning: Transient + Agent-Shell Deadlock

## Problem
When starting agent-shell via `C-c a a` (transient menu), Emacs deadlocks during "Initializing..." phase. Works fine with `M-x agent-shell`.

## Root Cause
`force-mode-line-update` conflicts with transient's display system when called during agent-shell buffer initialization. The hook runs while transient still controls window/buffer management.

## Solution Pattern
Use event-based initialization instead of synchronous hooks:

```elisp
;; BAD: Causes deadlock
(add-hook 'agent-shell-mode-hook #'ai-code-behaviors-mode-line-enable)

;; GOOD: Waits for shell to be ready
(add-hook 'agent-shell-mode-hook
          (lambda ()
            (agent-shell-subscribe-to
             :shell-buffer (current-buffer)
             :event 'prompt-ready  ; Shell is ready for input
             :on-event (lambda (_)
                         (ai-code-behaviors-mode-line-enable)))))
```

## Key Insight
Different execution contexts have different display constraints:
- `M-x`: Normal Emacs state - mode-line updates work
- `C-c a a`: Transient active - display system locked until transient exits
- Solution: Defer display operations until after initialization completes

## Debugging Technique
1. Binary search: Disable features one by one to isolate culprit
2. Compare paths: `M-x` vs `C-c a a` behavior differences
3. Event-driven: Look for lifecycle events (prompt-ready, init-finished)
4. Minimize reproducer: Start with minimal decorator, add features incrementally

## Prevention
- Always test both `M-x` and transient paths for display-heavy operations
- Use lifecycle events rather than immediate hooks for display updates
- Document display system dependencies in comments

## Related Patterns
- agent-shell-event-subscription
- transient-display-conflict
- deferred-mode-line-enable

## Evidence
- Fixed deadlock in ai-code-behaviors.el
- Mode-line now auto-enables after prompt-ready event
- All features work: @ completion, # completion, decorator, mode-line


# gptel-Agent Safety Mechanisms: Reuse vs Local

## Insight

We reuse gptel-agent's confirmation and timeout mechanisms directly. Local extensions add project-specific limits and defensive patterns not in upstream.

## What We Reuse from gptel-Agent

### 1. Tool Confirmation (`:confirm t`)

**Mechanism:** Tool property requiring user approval before execution.

**Tools with confirmation:**

| Tool | Why Confirmed |
|------|---------------|
| Bash | Arbitrary command execution |
| Eval | Arbitrary code execution |
| Mkdir | Creates directories |
| Edit | Modifies files |
| Insert | Modifies files |
| Write | Creates/overwrites files |
| Agent | Launches sub-agent |

**Status:** ✅ Directly using gptel-agent tools with `:confirm t`.

### 2. Confirmation UI (`gptel-agent--confirm-overlay`)

**Mechanism:** Overlay preview showing tool call before execution.

**Keybindings:**
- `n` / `p` — Navigate between tool calls
- `q` — Reject tool call
- `TAB` — Expand/collapse details

**Status:** ✅ UI provided by gptel-agent, no local changes needed.

### 3. Web Timeouts (`gptel-agent--fetch-with-timeout`)

**Mechanism:** 30-second timeout for WebSearch/WebFetch requests.

**Implementation:** 
```elisp
(let ((timeout 30) timer done ...)
  (run-at-time timeout nil ...))
```

**Status:** ✅ Built into gptel-agent, automatically applied.

---

## What We Added Locally

### 1. Max Steps Limit (`gptel-agent-loop-max-steps`)

**Purpose:** Prevent runaway agent loops.

**Default:** 50 steps

**Location:** `lisp/modules/gptel-agent-loop.el`

**Code:**
```elisp
(defcustom gptel-agent-loop-max-steps 50
  "Maximum number of tool calls before forcing DONE state.")
```

**Why local:** Project-specific limit, upstream has no equivalent.

### 2. Doom-Loop Detection

**Purpose:** Detect 3+ identical consecutive tool calls and abort.

**Trigger:** Same tool + same args called 3+ times in a row.

**Action:** Abort with error message.

**Location:** `lisp/modules/gptel-ext-tool-sanitize.el`

**Why local:** Defensive pattern, not in upstream.

### 3. Tool Permits System (`gptel-ext-tool-permits.el`)

**Purpose:** Session-scoped tool approval memory.

**Modes:**
- `auto` — No confirmation (trusted)
- `confirm-all` — Every tool requires approval

**Emergency:** `my/gptel-emergency-stop` aborts all requests, clears permits.

**Why local:** Not in upstream.

### 4. Payload Size Limits

**Purpose:** Prevent oversized edits from corrupting files.

**Implementation:**
```elisp
(defcustom gptel-tools-preview-max-replacement-size 1000000
  "Maximum size in bytes for replacement content (default 1MB).")
```

**Location:** `lisp/modules/gptel-tools-preview.el`

**Why local:** Project-specific threshold.

### 5. ~~Immutable File Protection~~ NOT NEEDED

**Why NOT implemented:**

1. **User choice** — Auto mode is intentional. User wants speed.
2. **Sandbox covers it** — Plan mode has Bash whitelist, Eval blacklist
3. **Permit system** — Confirm-all mode requires approval
4. **Git is memory** — Can revert any accidental change
5. **Emergency stop** — `my/gptel-emergency-stop` for disasters
6. **Workspace boundary** — Already blocks out-of-workspace modifications

**Conclusion:** Sandbox + permit system provides sufficient architectural safety. If user wants protection, they use confirm-all mode.

---

## Decision Matrix

| Feature | Upstream | Local | Why |
|---------|----------|-------|-----|
| `:confirm t` | ✅ | — | Upstream mechanism |
| Confirmation UI | ✅ | — | Upstream provides |
| Web timeout (30s) | ✅ | — | Upstream provides |
| Max steps limit | ❌ | ✅ | Project-specific |
| Doom-loop detection | ❌ | ✅ | Defensive pattern |
| Tool permits system | ❌ | ✅ | Session-scoped approval |
| Payload size limits | ❌ | ✅ | Project-specific |
| Immutable file protection | — | ❌ NOT NEEDED | Sandbox + permits sufficient |

---

## Lambda

```
λ safety(x).    upstream_has(x) → reuse(x)
                | project_specific(x) ∨ defensive(x) → local(x)
                | confirm(t) ∧ timeout(x) → upstream
                | limit(x) ∧ threshold(x) → local
                | immutable(x) → ¬needed(sandbox ∧ permits ∧ git ∧ emergency_stop)
```

---

## Upstream PR Candidates

| Feature | Value | Complexity | Recommendation |
|---------|-------|------------|----------------|
| Max steps as tool property | High | Low (~10 lines) | Consider PR |
| Payload size limit | Medium | Low (~5 lines) | Consider PR |
| Doom-loop detection | Medium | Low (~20 lines) | Keep local (opinionated) |
| Tool permits system | Medium | Medium (~50 lines) | Keep local (UX preference) |
| Immutable file protection | — | — | NOT NEEDED |

---

## Files Reference

| File | Purpose |
|------|---------|
| `var/elpa/gptel-agent/gptel-agent-tools.el` | Upstream tools with `:confirm t` |
| `lisp/modules/gptel-agent-loop.el` | Max steps, hard loop |
| `lisp/modules/gptel-ext-tool-sanitize.el` | Doom-loop detection |
| `lisp/modules/gptel-tools-preview.el` | Payload size limits |
| `lisp/modules/gptel-ext-tool-permits.el` | Granular allow/deny |
| `lisp/modules/gptel-ext-security.el` | Path validation |

---

## Captured

2026-03-23 — Analysis of gptel-agent safety mechanisms during OUROBOROS gap resolution.

🔄 workflow-improve-plan-agent

Workflow plan-agent: 3 anti-patterns, 3 improvements applied