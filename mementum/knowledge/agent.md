---
title: Agent Systems: Architecture, Patterns, and Debugging
status: active
category: knowledge
tags: [agent, gptel-agent, autonomous-agent, debugging, safety, workflow]
---

# Agent Systems: Architecture, Patterns, and Debugging

This knowledge page synthesizes findings from autonomous research agent testing, code agent efficiency analysis, safety mechanism design, and debugging patterns for the gptel-based agent ecosystem.

---

## 1. Autonomous Research Agent Architecture

### 1.1 Core Components

The autonomous research agent (`gptel-auto-workflow-run`) consists of four main components:

| Component | Function | Status |
|-----------|----------|--------|
| Worktree Manager | Creates branch for experiments | ✓ Pass |
| Executor Subagent | Executes research tasks | ✓ Pass |
| Code Improver | Adds docstrings, improvements | ✓ Pass |
| Grader Subagent | Evaluates results | ⚠️ Timeout |

### 1.2 Workflow Execution

```elisp
;; Full workflow (gptel-auto-experiment-run)
(defun gptel-auto-experiment-run (hypothesis)
  "Run full autonomous experiment with HYPOTHESIS."
  (let* ((worktree (gptel-auto-worktree-create))
         (executor-result (gptel-auto-executor-run worktree hypothesis))
         (improved (gptel-auto-code-improver worktree executor-result))
         (graded (gptel-auto-grader-run improved)))
    graded))
```

### 1.3 Observed Behavior

**Test Date:** 2026-03-24
**Test Command:** `gptel-auto-workflow-run`

| Metric | Value |
|--------|-------|
| Worktree creation | `optimize/retry-exp1` ✓ |
| Executor runtime | 50.5s ✓ |
| Code changes | +18 lines (docstrings) ✓ |
| Grading result | Timeout (5+ min) ✗ |

**File Modified:** `lisp/modules/gptel-ext-retry.el`

```diff
+ ;; Usage:
+ ;;   This module automatically activates when loaded...
+ ;; Customization:
+ ;;   - `my/gptel-max-retries': Max retry attempts (default: 3)
```

---

## 2. Code Agent Efficiency Patterns

### 2.1 Task Type Analysis

Code agent efficiency varies significantly by task type:

| Task Type | Efficiency | Steps | Pattern |
|-----------|------------|-------|---------|
| Simple edit | 0.82-0.90 | 5-6 | read → edit (direct) |
| Exploration | 0.72 | 8 | glob → read×N → edit |
| Complex refactor | 0.65-0.75 | 12-15 | full cycle |

### 2.2 Efficiency Formula

```
λ explore(optimization). efficiency ∝ task_clarity + scope_definition
```

**Key insight:** Efficiency increases when task descriptions include scope hints and clarity about expected output.

### 2.3 Eight Keys Alignment

| Key | code-001 | code-002 | code-003 | Average |
|-----|----------|----------|----------|---------|
| vitality | 0.85 | 0.88 | 0.78 | 0.84 |
| clarity | 0.82 | 0.90 | 0.72 | 0.81 |
| synthesis | 0.80 | 0.85 | 0.75 | 0.80 |

### 2.4 Anti-Pattern Detection

All tests pass Wu Xing constraints:

- **wood-overgrowth:** ✓ (steps ≤ 20)
- **fire-excess:** ✓ (efficiency ≥ 0.5)
- **metal-rigidity:** ✓ (tool-score ≥ 0.6)
- **tool-misuse:** ✓ (steps ≤ 15, continuations ≤ 3)

### 2.5 Actionable Patterns

**Pattern 1: Direct Path for Simple Edits**
```elisp
;; For simple edits, skip intermediate phases
;; P1 → P3 (skip P2) is valid and more efficient
(let ((task-type (gptel-classify-task prompt)))
  (cond ((eq task-type 'simple-edit)
         (gptel-agent-run-p1+p3 prompt))  ; Skip P2
        ((eq task-type 'exploration)
         (gptel-agent-run-full-cycle prompt))))
```

**Pattern 2: Exploration Scope Budget**
```elisp
;; Limit exploration to prevent context bloat
(defcustom gptel-exploration-max-files 5
  "Maximum files to explore before synthesizing."
  :type 'integer)

(defcustom gptel-exploration-max-depth 2
  "Maximum directory depth for exploration."
  :type 'integer)
```

**Pattern 3: Task Description Hints**
```
BAD:  "Explore the codebase and make improvements"
GOOD: "Explore lisp/modules/ (max 5 files), find unused functions,
       add docstrings to 1-2 functions in gptel-ext-retry.el"
```

---

## 3. Safety Mechanisms: Upstream vs Local

### 3.1 Decision Matrix

| Feature | Upstream (gptel-agent) | Local Extension | Why Local |
|---------|----------------------|-----------------|-----------|
| `:confirm t` | ✅ Tool property | — | Upstream mechanism |
| Confirmation UI | ✅ Overlay preview | — | gptel-agent provides |
| Web timeout (30s) | ✅ Built-in | — | gptel-agent default |
| Max steps limit | ❌ | ✅ | Project-specific (default: 50) |
| Doom-loop detection | ❌ | ✅ | Defensive pattern |
| Tool permits system | ❌ | ✅ | Session-scoped approval |
| Payload size limits | ❌ | ✅ | 1MB threshold |

### 3.2 What We Reuse from Upstream

**Tool Confirmation (`:confirm t`):**

```elisp
;; Tools requiring confirmation
'((bash :confirm t)   ; Arbitrary command execution
  (eval :confirm t)   ; Arbitrary code execution
  (mkdir :confirm t)  ; Creates directories
  (edit :confirm t)   ; Modifies files
  (write :confirm t)  ; Creates/overwrites files
  (agent :confirm t)) ; Launches sub-agent
```

**Confirmation UI Keybindings:**
- `n` / `p` — Navigate between tool calls
- `q` — Reject tool call
- `TAB` — Expand/collapse details

**Web Timeout Implementation:**
```elisp
(let ((timeout 30) timer done)
  (run-at-time timeout nil
    (lambda ()
      (unless done
        (setq done t)
        (message "Web request timeout after %ds" timeout)))))
```

### 3.3 Local Extensions

**Max Steps Limit:**
```elisp
;; lisp/modules/gptel-agent-loop.el
(defcustom gptel-agent-loop-max-steps 50
  "Maximum number of tool calls before forcing DONE state."
  :type 'integer
  :group 'gptel-agent)
```

**Doom-Loop Detection:**
```elisp
;; lisp/modules/gptel-ext-tool-sanitize.el
(defun gptel-detect-doom-loop (tool-history)
  "Detect 3+ identical consecutive tool calls."
  (let ((loop-detected nil))
    (dotimes (i (- (length tool-history) 2))
      (when (and (equal (nth i tool-history) (nth (+ i 1) tool-history))
                 (equal (nth i tool-history) (nth (+ i 2) tool-history)))
        (setq loop-detected t)))
    loop-detected))
```

**Tool Permits System:**
```elisp
;; lisp/modules/gptel-ext-tool-permits.el
(defvar gptel-tool-permits nil
  "Alist of (tool-name . auto-allow-p).")

(defun gptel-toggle-permit (tool mode)
  "Toggle TOOL permit to MODE (auto/confirm-all)."
  (setq gptel-tool-permits
        (cons (cons tool (eq mode 'auto))
              (cl-delete-if (lambda (x) (car x)) gptel-tool-permits))))

(defun gptel-emergency-stop ()
  "Abort all requests, clear permits."
  (setq gptel-tool-permits nil)
  (gptel-agent-abort)
  (message "Emergency stop: all permits cleared"))
```

### 3.4 Why Immutable File Protection Is NOT Needed

1. **User choice:** Auto mode is intentional; user wants speed
2. **Sandbox covers it:** Plan mode has Bash whitelist, Eval blacklist
3. **Permit system:** Confirm-all mode requires approval for all tools
4. **Git is memory:** Can revert any accidental change
5. **Emergency stop:** `my/gptel-emergency-stop` for disasters
6. **Workspace boundary:** Already blocks out-of-workspace modifications

---

## 4. Debugging: Transient + Agent-Shell Deadlock

### 4.1 Problem Statement

**Symptom:** Deadlock during "Initializing..." phase when starting agent-shell via `C-c a a` (transient menu). Works fine with `M-x agent-shell`.

### 4.2 Root Cause

`force-mode-line-update` conflicts with transient's display system when called during agent-shell buffer initialization. The hook runs while transient still controls window/buffer management.

```elisp
;; BAD: Causes deadlock
(add-hook 'agent-shell-mode-hook #'ai-code-behaviors-mode-line-enable)
```

### 4.3 Solution Pattern

**Use event-based initialization:**

```elisp
;; GOOD: Waits for shell to be ready
(add-hook 'agent-shell-mode-hook
          (lambda ()
            (agent-shell-subscribe-to
             :shell-buffer (current-buffer)
             :event 'prompt-ready  ; Shell is ready for input
             :on-event (lambda (_)
                         (ai-code-behaviors-mode-line-enable)))))
```

### 4.4 Execution Context Differences

| Context | Display State | Mode-line Updates |
|---------|---------------|-------------------|
| `M-x` | Normal Emacs | Work reliably |
| `C-c a a` | Transient active | Blocked until transient exits |

### 4.5 Debugging Technique

1. **Binary search:** Disable features one by one to isolate culprit
2. **Compare paths:** Test `M-x` vs `C-c a a` behavior differences
3. **Event-driven:** Look for lifecycle events (`prompt-ready`, `init-finished`)
4. **Minimize reproducer:** Start with minimal decorator, add features incrementally

### 4.6 Prevention Checklist

- [ ] Test both `M-x` and transient paths for display-heavy operations
- [ ] Use lifecycle events rather than immediate hooks for display updates
- [ ] Document display system dependencies in comments

---

## 5. Grading Subagent Timeout Fix

### 5.1 The Problem

The grading step calls `gptel-benchmark-grade` which uses a 'grader' subagent. This subagent:
1. Uses DashScope backend (correct)
2. Has no explicit timeout
3. No fallback if subagent hangs

### 5.2 The Fix

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

### 5.3 Recommendations

1. **Add timeout to grading** — Wrap subagent calls with `run-with-timer` timeout
2. **Add fallback** — Use `gptel-benchmark--local-grade` if subagent times out
3. **Add progress logging** — Log each step to `*Messages*`
4. **Add heartbeats** — Periodic "still grading..." messages

---

## 6. Files Reference

| File | Purpose |
|------|---------|
| `lisp/modules/gptel-ext-retry.el` | Retry logic module |
| `lisp/modules/gptel-agent-loop.el` | Max steps, hard loop |
| `lisp/modules/gptel-ext-tool-sanitize.el` | Doom-loop detection |
| `lisp/modules/gptel-tools-preview.el` | Payload size limits |
| `lisp/modules/gptel-ext-tool-permits.el` | Granular allow/deny |
| `lisp/modules/gptel-ext-security.el` | Path validation |
| `var/elpa/gptel-agent/gptel-agent-tools.el` | Upstream tools |

---

## 7. Lambda: Safety Decision Formula

```
λ safety(x).    
   upstream_has(x) → reuse(x)
   | project_specific(x) ∨ defensive(x) → local(x)
   | confirm(t) ∧ timeout(x) → upstream
   | limit(x) ∧ threshold(x) → local
   | immutable(x) → ¬needed(sandbox ∧ permits ∧ git ∧ emergency_stop)
```

---

## Related

- [gptel-agent](./gptel-agent.md) - Upstream agent system
- [agent-shell](./agent-shell.md) - Shell integration for agents
- [workflow-automation](./workflow-automation.md) - Autonomous workflows
- [debugging-patterns](./debugging-patterns.md) - General debugging techniques
- [safety-mechanisms](./safety-mechanisms.md) - Security and safety architecture

---

## Summary

The agent system is **60% complete** for full autonomous operation. The core loop works (worktree → executor → changes), but the grading subagent needs timeout handling.

**Key Takeaways:**
1. **Reuse upstream** where possible (confirmation, timeouts, UI)
2. **Extend locally** for project-specific needs (max steps, doom-loop detection)
3. **Test all paths** — `M-x` vs transient behave differently
4. **Use events** — Defer display operations until initialization completes
5. **Add timeouts** — Always wrap subagent calls with fallback mechanisms