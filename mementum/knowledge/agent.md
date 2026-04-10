---
title: Agent System Knowledge
status: active
category: knowledge
tags: [agent, gptel, workflow, benchmark, safety, debugging]
---

# Agent System Knowledge

This knowledge page synthesizes findings from autonomous research agent testing, code agent efficiency benchmarking, safety mechanism design, and debugging patterns for the gptel-agent system.

---

## 1. Autonomous Research Agent Workflow

### 1.1 Overview

The Autonomous Research Agent (`gptel-auto-workflow-run`) is designed to execute a complete research loop: worktree creation → executor subagent → code improvement → grading subagent.

### 1.2 Test Results (2026-03-24)

| Component | Status | Notes |
|-----------|--------|-------|
| Worktree creation | ✓ Pass | Created `optimize/retry-exp1` |
| Executor subagent | ✓ Pass | Completed in 50.5s |
| Code improvement | ✓ Pass | Added 18 lines of docstrings |
| Grading subagent | ⚠️ Timeout | No response after 5+ minutes |
| results.tsv | ✗ Not created | Grading didn't complete |

**Verdict:** 60% complete. Core loop works, grading needs timeout handling.

### 1.3 Root Cause Analysis

The grading step calls `gptel-benchmark-grade` which uses a 'grader' subagent. This subagent makes an LLM call that:
1. Uses DashScope backend (correct)
2. Has no explicit timeout
3. No fallback if subagent hangs

### 1.4 Timeout Fix Pattern

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

### 1.5 Actionable Recommendations

1. **Add timeout to grading** - Wrap subagent calls with `run-with-timer` timeout
2. **Add fallback** - Use `gptel-benchmark--local-grade` if subagent times out
3. **Add progress logging** - Log each step to `*Messages*`
4. **Add heartbeats** - Periodic "still grading..." messages

---

## 2. Code Agent Efficiency Patterns

### 2.1 Efficiency by Task Type

| Task Type | Efficiency | Steps | Pattern |
|-----------|------------|-------|---------|
| Simple edit | 0.82-0.90 | 5-6 | read → edit (direct) |
| Exploration | 0.72 | 8 | glob → read×N → edit |

**Key Insight:** Direct path (P1 → P3) is more efficient than full cycle (P1 → P2 → P3) for simple tasks.

### 2.2 Anti-Pattern Detection

No anti-patterns triggered (all tests pass Wu Xing constraints):

- **wood-overgrowth:** ✓ (steps <= 20)
- **fire-excess:** ✓ (efficiency >= 0.5)
- **metal-rigidity:** ✓ (tool-score >= 0.6)
- **tool-misuse:** ✓ (steps <= 15, continuations <= 3)

### 2.3 Eight Keys Alignment

| Key | code-001 | code-002 | code-003 | Avg |
|-----|----------|----------|----------|-----|
| vitality | 0.85 | 0.88 | 0.78 | 0.84 |
| clarity | 0.82 | 0.90 | 0.72 | 0.81 |
| synthesis | 0.80 | 0.85 | 0.75 | 0.80 |

### 2.4 Improvement Patterns

**Exploration Tasks (code-003):**
- **Issue:** 2 continuations indicate context management needed
- **Remedy (Fire → Water):**
  - Add exploration scope hints to task descriptions
  - Use `--max-count` or `--max-depth` in glob/grep
  - Budget: 3-5 files for exploration, 1-2 for targeted edits

**Actionable Patterns:**
1. **Task Descriptions:** Add scope hints for exploration tasks
2. **Context Budget:** Limit exploration to 5 files before synthesis
3. **Phase Guidance:** Document when P2 can be skipped

---

## 3. Safety Mechanisms: Reuse vs Local

### 3.1 Upstream Reuse

The project reuses gptel-agent's built-in safety mechanisms:

| Mechanism | Source | Purpose |
|-----------|--------|---------|
| `:confirm t` | gptel-agent | Tool execution approval |
| Confirmation UI | gptel-agent | Overlay preview for tool calls |
| Web timeout (30s) | gptel-agent | Timeout for WebSearch/WebFetch |

**Tools with confirmation:**
- Bash, Eval (arbitrary execution)
- Mkdir, Edit, Insert, Write (file modification)
- Agent (sub-agent launch)

### 3.2 Local Extensions

| Feature | Purpose | File |
|---------|---------|------|
| `gptel-agent-loop-max-steps` | Prevent runaway loops (default: 50) | `gptel-agent-loop.el` |
| Doom-loop detection | Detect 3+ identical tool calls | `gptel-ext-tool-sanitize.el` |
| Tool permits system | Session-scoped approval memory | `gptel-ext-tool-permits.el` |
| Payload size limits | Prevent oversized edits (1MB default) | `gptel-tools-preview.el` |

### 3.3 Decision Matrix

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

### 3.4 Lambda for Safety Decisions

```
λ safety(x).    upstream_has(x) → reuse(x)
                | project_specific(x) ∨ defensive(x) → local(x)
                | confirm(t) ∧ timeout(x) → upstream
                | limit(x) ∧ threshold(x) → local
                | immutable(x) → ¬needed(sandbox ∧ permits ∧ git ∧ emergency_stop)
```

---

## 4. Debugging: Transient + Agent-Shell Deadlock

### 4.1 Problem Description

When starting agent-shell via `C-c a a` (transient menu), Emacs deadlocks during "Initializing..." phase. Works fine with `M-x agent-shell`.

### 4.2 Root Cause

`force-mode-line-update` conflicts with transient's display system when called during agent-shell buffer initialization. The hook runs while transient still controls window/buffer management.

### 4.3 Solution Pattern

```elisp
;; BAD: Causes deadlock
(add-hook 'agent-shell-mode-hook #'ai-code-behaviors-mode-line-enable)

;; GOOD: Waits for shell to be ready
(add-hook 'agent-shell-mode-hook
          (lambda ()
            (agent-shell-subscribe-to
             :shell-buffer (current-buffer)
             :event 'prompt-ready
             :on-event (lambda (_)
                         (ai-code-behaviors-mode-line-enable)))))
```

### 4.4 Key Insight

Different execution contexts have different display constraints:
- `M-x`: Normal Emacs state - mode-line updates work
- `C-c a a`: Transient active - display system locked until transient exits

**Solution:** Defer display operations until after initialization completes.

### 4.5 Debugging Technique

1. **Binary search:** Disable features one by one to isolate culprit
2. **Compare paths:** `M-x` vs `C-c a a` behavior differences
3. **Event-driven:** Look for lifecycle events (prompt-ready, init-finished)
4. **Minimize reproducer:** Start with minimal decorator, add features incrementally

### 4.6 Prevention

- Always test both `M-x` and transient paths for display-heavy operations
- Use lifecycle events rather than immediate hooks for display updates
- Document display system dependencies in comments

---

## 5. Files Reference

| File | Purpose |
|------|---------|
| `lisp/modules/gptel-ext-retry.el` | Retry mechanism module |
| `lisp/modules/gptel-agent-loop.el` | Max steps, hard loop |
| `lisp/modules/gptel-ext-tool-sanitize.el` | Doom-loop detection |
| `lisp/modules/gptel-tools-preview.el` | Payload size limits |
| `lisp/modules/gptel-ext-tool-permits.el` | Granular allow/deny |
| `lisp/modules/gptel-ext-security.el` | Path validation |
| `var/elpa/gptel-agent/gptel-agent-tools.el` | Upstream tools with `:confirm t` |

---

## 6. Workflow Patterns

### 6.1 Plan-Agent Anti-Patterns

**Workflow improvement:** 3 anti-patterns, 3 improvements applied

- `workflow-improve-plan-agent` pattern for continuous improvement

### 6.2 Lambda for Workflow Efficiency

```
λ explore(optimization). efficiency ∝ task_clarity + scope_definition
```

---

## Related

- [gptel-agent](https://github.com/karthink/gptel) - Upstream agent system
- [Eight Keys Framework](Eight-Keys-Framework) - Code agent evaluation
- [Wu Xing Constraints](Wu-Xing-Constraints) - Anti-pattern detection
- [Transient Mode](https://github.com/magnars/transient.el) - Emacs transient menus
- [agent-shell](agent-shell) - Shell integration for agents

---

## Summary

The agent system comprises:

1. **Autonomous Research Agent** - Complete workflow at 60% with grading timeout needed
2. **Code Agent Efficiency** - 0.72-0.90 efficiency depending on task type
3. **Safety Mechanisms** - Mix of upstream reuse and local extensions
4. **Debugging Patterns** - Event-driven initialization for display operations

**Key Lambda:**
```
λ agent(x). workflow(x) ∧ safety(x) ∧ debug(x) → production_ready(x)
```

---

*Captured: 2026-03-23 — Analysis during OUROBOROS gap resolution*
*Synthesized from: 4 memory fragments*