---
title: Subagent Architecture and Debugging
status: active
category: knowledge
tags: [subagent, gptel, emacs, agent, debugging, overlay]
---

# Subagent Architecture and Debugging

This knowledge page covers the subagent pattern in the gptel/Emacs ecosystem, including decision frameworks for when to use subagents, implementation patterns, and detailed debugging guides for common issues.

## 1. Understanding Subagents

A **subagent** is a dedicated agent spawned by a parent agent with its own context, model, and tool profile. Unlike skills which share the parent's context, subagents provide:

- **Context isolation** - Parent's context remains uncluttered
- **Parallel execution** - Can run concurrently with parent tasks
- **Dedicated model** - Use cheaper/faster models for specific tasks
- **Custom tool profile** - Restrict tools to only what's needed

## 2. Decision Matrix: Subagent vs Skill vs Protocol

Choose the right pattern based on your task requirements:

| Pattern | Use When | Location | Context |
|---------|----------|----------|---------|
| **Protocol** | Pure procedure, no external dependencies | `mementum/knowledge/{name}-protocol.md` | Shared |
| **Skill** | Has external tools/API, needs REPL | `assistant/skills/{name}/` | Shared |
| **Subagent** | Context isolation, parallel execution, dedicated model | `eca/prompts/{name}_agent.md` | Isolated |

### When to Choose Subagent

| Task Type | Use Subagent? | Reason |
|-----------|---------------|--------|
| Code review | ✅ Yes | Context isolation, readonly tools |
| Grading/evaluation | ✅ Yes | Dedicated model, parallel execution |
| File search | ✅ Yes | Isolated context for expensive operations |
| Quick Q&A | ❌ No | Overhead too high, use skill |
| Format conversion | ❌ No | Simple procedure, use protocol |

## 3. Configuration Structure

### ECA Subagent Config (eca/config.json)

```json
{
  "reviewer": {
    "system-prompt": "You are a code reviewer...",
    "model": "gpt-4.4-mini",
    "tools": ["read-file", "grep", "git-diff"],
    "timeout": 300
  },
  "grader": {
    "system-prompt": "You are a grader evaluating...",
    "model": "qwen3.5-plus",
    "tools": ["read-file", "execute-command"],
    "timeout": 600
  }
}
```

### Subagent Prompt Template (eca/prompts/reviewer_agent.md)

```markdown
# Code Reviewer Subagent

## Role
You are a senior code reviewer. Analyze the provided code changes.

## Constraints
- Don't modify code, only review
- Use readonly tools only
- Report issues, don't fix them

## Output Format
```json
{
  "issues": [{"severity": "high", "line": 42, "message": "..."}],
  "approval": false
}
```
```

## 4. Implementation Patterns

### Pattern 1: Spawning a Subagent

```elisp
(defun my/spawn-reviewer (file)
  "Spawn reviewer subagent for FILE."
  (let ((gptel-agent--task nil)
        (gptel-agent--agents '(reviewer)))
    (gptel-agent--task "Review this code" file)))
```

### Pattern 2: Defining Tool Profile

```elisp
(defvar gptel-agent--agents
  '((reviewer . ((model . "gpt-4.4-mini")
                 (tools . (read-file grep git-diff))
                 (system . "You are a code reviewer...")))))
```

### Pattern 3: Context Isolation

```elisp
(defun my/isolated-execution (task-fn)
  "Execute TASK-FN in isolated subagent context."
  (let ((gptel-parent-context nil))
    (funcall task-fn)))
```

## 5. Debugging Guide: Grader Subagent Fallback

### Problem Statement

Grader subagent always falls back to local grading instead of using LLM.

### Debugging Workflow

```bash
# 1. Run diagnostic tests
./scripts/run-tests.sh grader

# 2. Check function existence
(fboundp 'gptel-agent--task)  ; Should return t

# 3. Verify agent loaded
:gptel-agent-loaded t
:gptel-agent--task-fbound t  
:gptel-agent--agents-count 13
```

### Root Cause Analysis

| Check | Command | Expected | Actual | Fix |
|-------|---------|----------|--------|-----|
| Require loaded | `(require 'gptel-agent)` | No error | Failed | Add require at top |
| Function defined | `(fboundp 'gptel-agent--task)` | t | nil | Check defun |
| Variable shadow | `(boundp 'gptel-agent--agents)` | t | nil | Remove defvar |
| Agents populated | `gptel-agent--agents` | non-nil | nil | Check config |

### Common Fixes

#### Fix 1: Missing Require

```elisp
;;; gptel-tools-agent.el -*- lexical-binding: t -*-
(require 'gptel-agent)  ; ADD THIS at top of file
(require 'gptel-core)
```

#### Fix 2: Remove Redundant Variable Declaration

```elisp
;; BAD - shadows the real variable
(defvar gptel-agent--agents nil)

;; GOOD - use the actual definition from gptel-agent.el
```

#### Fix 3: JSON Parser for Grader Output

```elisp
(defun gptel-benchmark--parse-grader-output (output)
  "Parse grader OUTPUT JSON string."
  (let* ((json-key-type 'string)
         (parsed (json-parse-string output :object-type 'plist)))
    (list :score (plist-get parsed :score)
          :feedback (plist-get parsed :feedback))))
```

## 6. Overlay Conflict Resolution

### Problem

Subagent overlays appear in wrong buffer (*Messages*) despite routing fixes.

### Root Cause

**Conflicting advices** on `gptel-agent--task`:

| Advice | Type | Location | Issue |
|--------|------|----------|-------|
| `my/gptel-agent--task-override` | `:override` | gptel-tools-agent.el:461 | Replaces function entirely |
| `gptel-auto-workflow--advice-task-override` | `:around` | gptel-auto-workflow-projects.el:212 | Wraps function |

The `:override` advice completely replaces the original function and creates overlays in `parent-buf`, which can be `*Messages*` if the FSM was created there.

### Symptoms

- Overlays appear in *Messages* buffer after "fixes"
- Executor and Grader overlays visible in wrong buffer
- "Buffer gptel.el modified; kill anyway?" prompts in headless mode

### Solution

```elisp
;; 1. REMOVE old :override advice
(advice-remove 'gptel-agent--task 'my/gptel-agent--task-override)

;; 2. Merge caching into :around advice
(defadvice gptel-agent--task (around gptel-auto-workflow--advice-task-override activate)
  "Add caching and workflow routing to gptel-agent--task."
  (let ((cache-key (cons (ad-get-arg 0) (ad-get-arg 1))))
    (if (aget gptel-agent--cache cache-key)
        (message "Using cached result")
      (progn
        ad-do-it
        (aput gptel-agent--cache cache-key ad-return-value)))))

;; 3. Suppress kill-buffer query in headless mode
(setq kill-buffer-query-functions 
      (delq 'process-kill-buffer-query-function kill-buffer-query-functions))
```

### Pattern: Single Advice Rule

```
┌─────────────────────────────────────────────┐
│  ONE advice per function                    │
│  Use :around for wrapping                  │
│  Never use :override unless replacing ALL  │
└─────────────────────────────────────────────┘
```

## 7. Verification Checklist

After implementing subagent fixes, verify with:

```elisp
;; In *scratch* or diagnostic buffer
(mapcar (lambda (check)
          (pcase check
            ('require-loaded (require 'gptel-agent) t)
            ('task-fbound (fboundp 'gptel-agent--task))
            ('agents-count (length gptel-agent--agents))
            ('model-set (assoc 'grader gptel-agent--agents))))
        '(require-loaded task-fbound agents-count model-set))
```

Expected output:
```elisp
(require-loaded . t)
(task-fbound . t)
(agents-count . 13)
(model-set . (grader . [...]))
```

## 8. Testing Pattern (TDD)

Write tests first to guide fixes:

```elisp
;;; tests/test-grader-subagent.el
(require 'ert)
(require 'gptel-tools-agent)

(ert-deftest test-grader-uses-llm ()
  "Test that grader uses LLM instead of local fallback."
  (let ((gptel-agent--agents '((grader . ((model . "qwen3.5-plus"))))))
    (should (eq (gptel-grader--select-mode) 'llm))))

(ert-deftest test-grader-json-parser ()
  "Test JSON parsing of grader output."
  (let ((output "{\"score\": 85, \"feedback\": \"Good work\"}"))
    (should (equal (gptel-benchmark--parse-grader-output output)
                   '(:score 85 :feedback "Good work")))))
```

Run tests:
```bash
./scripts/run-tests.sh grader
```

## 9. Key Files Reference

| File | Purpose | Key Functions |
|------|---------|---------------|
| `gptel-agent.el` | Core agent definition | `gptel-agent--task`, `gptel-agent--agents` |
| `gptel-tools-agent.el` | Tool-using agents | `require 'gptel-agent` |
| `gptel-benchmark-subagent.el` | Grader implementation | JSON parsing |
| `gptel-auto-workflow-projects.el` | Workflow routing | `:around` advice |
| `tests/test-grader-subagent.el` | Tests | 8 test cases |

## Related

- [Agent Architecture](./agent-architecture.md) - Parent agent patterns
- [Skill vs Subagent Decision](./skill-vs-subagent.md) - Selection criteria
- [gptel-agent Debugging](./gptel-debugging.md) - General debugging guide
- [Emacs Advice Patterns](./emacs-advice.md) - Advice implementation
- [Context Isolation](./context-isolation.md) - Memory management
- [ECA Configuration](./eca-config.md) - Subagent config format

---

*Last updated: 2026-03-29*
*Status: Active - Maintained*
*Category: Architecture/Debugging*