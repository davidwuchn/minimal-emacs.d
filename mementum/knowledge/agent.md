---
title: Agent Systems Knowledge Base
status: active
category: knowledge
tags: [agent, gptel, autonomous, workflow, debugging, safety]
---

# Agent Systems Knowledge Base

This page consolidates knowledge about autonomous agent systems in this Emacs environment, covering architecture, efficiency patterns, safety mechanisms, and debugging guidance.

## Architecture Overview

### Autonomous Research Agent (ARA) Architecture

The ARA system consists of four main components that execute in sequence:

| Component | Purpose | Status | Notes |
|-----------|---------|--------|-------|
| Worktree creation | Isolated Git branch for changes | ✓ Pass | Creates `optimize/retry-expN` branches |
| Executor subagent | Execute task, make code changes | ✓ Pass | Completes in ~50 seconds |
| Code improvement | Add documentation, cleanup | ✓ Pass | Typical: +18 lines docstrings |
| Grading subagent | Evaluate results | ⚠️ Timeout | Needs timeout handling |

**Current State:** 60% complete. Core loop works; grading needs timeout handling.

### Execution Flow

```
Task Input → Worktree → Executor → Changes → Grading → Results
```

The grading step uses `gptel-benchmark-grade` which invokes a 'grader' subagent. This subagent makes an LLM call via DashScope backend with no explicit timeout, causing hangs.

---

## Efficiency Patterns

### Task Type Efficiency Matrix

| Task Type | Efficiency | Steps | Pattern |
|-----------|------------|-------|---------|
| Simple edit | 0.82-0.90 | 5-6 | read → edit (direct) |
| Exploration | 0.72 | 8 | glob → read×N → edit |

### Eight Keys Alignment

| Key | Simple Edit | Exploration | Average |
|-----|-------------|-------------|---------|
| vitality | 0.85 | 0.78 | 0.84 |
| clarity | 0.82 | 0.72 | 0.81 |
| synthesis | 0.80 | 0.75 | 0.80 |

### Anti-Pattern Detection (Wu Xing)

All tests pass these constraints:

- **wood-overgrowth**: ✓ (steps ≤ 20)
- **fire-excess**: ✓ (efficiency ≥ 0.5)
- **metal-rigidity**: ✓ (tool-score ≥ 0.6)
- **tool-misuse**: ✓ (steps ≤ 15, continuations ≤ 3)

### Improvement Patterns

**Issue:** Exploration tasks need 2+ continuations (context management problem)

**Remedy (Fire → Water):**
- Add exploration scope hints to task descriptions
- Use `--max-count` or `--max-depth` in glob/grep
- **Budget:** 3-5 files for exploration, 1-2 for targeted edits

**Phase Transition Observation:**
Simple edits often go P1 → P3 (skipping P2), which is valid and more efficient than full cycle.

---

## Safety Mechanisms

### What We Reuse from gptel-Agent

| Mechanism | Purpose | Status |
|-----------|---------|--------|
| `:confirm t` tool property | User approval before execution | ✓ Reused |
| Confirmation UI (`gptel-agent--confirm-overlay`) | Overlay preview of tool calls | ✓ Reused |
| Web timeouts (30s) | `gptel-agent--fetch-with-timeout` | ✓ Reused |

**Tools requiring confirmation:**
- Bash (arbitrary commands)
- Eval (arbitrary code)
- Mkdir, Edit, Insert, Write (file operations)
- Agent (sub-agent launches)

### What We Add Locally

| Feature | Purpose | Location |
|---------|---------|----------|
| Max steps limit | Prevent runaway loops (default: 50) | `gptel-agent-loop.el` |
| Doom-loop detection | Abort on 3+ identical consecutive calls | `gptel-ext-tool-sanitize.el` |
| Tool permits | Session-scoped approval memory | `gptel-ext-tool-permits.el` |
| Payload size limits | Prevent oversized edits (1MB default) | `gptel-tools-preview.el` |

### Decision Matrix

```
λ safety(x).    
  upstream_has(x) → reuse(x)
  | project_specific(x) ∨ defensive(x) → local(x)
  | confirm(t) ∧ timeout(x) → upstream
  | limit(x) ∧ threshold(x) → local
  | immutable(x) → ¬needed(sandbox ∧ permits ∧ git ∧ emergency_stop)
```

### Why Immutable File Protection Is NOT Needed

1. **User choice** — Auto mode is intentional, user wants speed
2. **Sandbox covers it** — Plan mode has Bash whitelist, Eval blacklist
3. **Permit system** — Confirm-all mode requires explicit approval
4. **Git is memory** — Can revert any accidental change
5. **Emergency stop** — `my/gptel-emergency-stop` for disasters
6. **Workspace boundary** — Already blocks out-of-workspace modifications

---

## Debugging Guide

### Transient + Agent-Shell Deadlock

**Problem:** When starting `agent-shell` via `C-c a a` (transient menu), Emacs deadlocks during "Initializing..." phase. Works fine with `M-x agent-shell`.

**Root Cause:** `force-mode-line-update` conflicts with transient's display system when called during buffer initialization. The hook runs while transient still controls window/buffer management.

#### Solution Pattern

Use event-based initialization instead of synchronous hooks:

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

#### Key Insight

Different execution contexts have different display constraints:
- `M-x`: Normal Emacs state — mode-line updates work
- `C-c a a`: Transient active — display system locked until transient exits
- **Solution:** Defer display operations until after initialization completes

#### Debugging Technique

1. **Binary search:** Disable features one by one to isolate culprit
2. **Compare paths:** `M-x` vs `C-c a a` behavior differences
3. **Event-driven:** Look for lifecycle events (`prompt-ready`, `init-finished`)
4. **Minimize reproducer:** Start with minimal decorator, add features incrementally

#### Prevention

- Always test both `M-x` and transient paths for display-heavy operations
- Use lifecycle events rather than immediate hooks for display updates
- Document display system dependencies in comments

---

## Grading Timeout Fix

### Problem

Grading subagent calls `gptel-benchmark-grade` which uses a 'grader' subagent making an LLM call with no explicit timeout. No fallback exists if subagent hangs.

### Solution Code

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

### Implementation Notes

- **Timeout:** 60 seconds before fallback
- **Fallback action:** Use `gptel-benchmark--local-grade` or default score
- **Logging:** Each step logged to `*Messages*`
- **Heartbeats:** Consider periodic "still grading..." messages

---

## File Reference

| File | Purpose |
|------|---------|
| `lisp/modules/gptel-ext-retry.el` | Autonomous experiment runner |
| `lisp/modules/gptel-agent-loop.el` | Max steps, hard loop |
| `lisp/modules/gptel-ext-tool-sanitize.el` | Doom-loop detection |
| `lisp/modules/gptel-tools-preview.el` | Payload size limits |
| `lisp/modules/gptel-ext-tool-permits.el` | Granular allow/deny |
| `lisp/modules/gptel-ext-security.el` | Path validation |
| `var/elpa/gptel-agent/gptel-agent-tools.el` | Upstream tools with `:confirm t` |

---

## Related

- [gptel](gptel) — LLM client for Emacs
- [agent-shell](agent-shell) — Shell buffer with agent integration
- [transient](transient) — Emacs transient menus
- [debugging](debugging) — General debugging patterns
- [workflow](workflow) — Workflow automation

---

## Lambda Summary

```
λ explore(optimization). efficiency ∝ task_clarity + scope_definition
```

**Key principle:** Clear task descriptions with explicit scope hints significantly improve agent efficiency, especially for exploration tasks.

---

*Last updated: 2026-03-24*
*Category: agent*
*Status: active*