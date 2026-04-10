---
title: Subagent Architecture in gptel.el
status: active
category: knowledge
tags: [gptel, subagent, agent-architecture, debugging, workflow]
---

# Subagent Architecture in gptel.el

## Overview

A **subagent** is a specialized agent spawned by the parent gptel process to handle specific tasks in isolation. Subagents provide context isolation, parallel execution, and dedicated tool profiles—making them ideal for tasks like code review, grading, or any work that shouldn't pollute the parent agent's context.

## Core Components

### Key Variables and Functions

| Symbol | Type | Purpose |
|--------|------|---------|
| `gptel-agent--task` | function | Main task dispatcher for subagents |
| `gptel-agent--agents` | alist | Registry of available subagent definitions |
| `gptel-auto-workflow--task-override` | advice | Routes tasks to appropriate subagent |
| `gptel-model` | variable | Current model for the parent agent |

### Required Load Order

```
gptel.el (core)
  └── gptel-agent.el (agent machinery)
        └── gptel-tools-agent.el (tool integration)
```

**Critical**: `gptel-tools-agent.el` must require `gptel-agent` to have access to `gptel-agent--task`:

```elisp
;; CORRECT: gptel-tools-agent.el
(require 'gptel-agent)  ; Must come BEFORE using gptel-agent--task
(require 'gptel-tools)   ; Tool definitions

(defun gptel-tools-agent--do-grading ()
  "Execute grading via LLM subagent."
  (when (fboundp 'gptel-agent--task)
    (gptel-agent--task "grade" :system grader-system-prompt ...)))
```

### Agent Registry Structure

```elisp
(defvar gptel-agent--agents
  '(("reviewer" . ,reviewer-config)
    ("grader"   . ,grader-config))
  "Alist of subagent name → configuration.")
```

## Decision Matrix: Subagent vs Skill vs Protocol

Choose based on task requirements:

| Criteria | Subagent | Skill | Protocol |
|----------|----------|-------|----------|
| Context isolation | ✅ Full | ❌ Shared | ❌ Shared |
| Parallel execution | ✅ Yes | ❌ Sequential | ❌ Sequential |
| Dedicated model | ✅ Yes | ❌ No | ❌ No |
| External tools/API | ✅ Via tool profile | ✅ Native | ❌ None |
| Setup complexity | Medium | Low | Lowest |
| Use case | Code review, grading | REPL, API calls | Pure procedures |

### When to Use Subagent

```elisp
;; Subagent is appropriate when:
(when (or context-isolation-needed      ; Review shouldn't pollute parent
          parallel-execution-needed      ; Spawn and continue work
          dedicated-model-desired        ; Use cheaper model for review
          readonly-tool-profile-needed)   ; Restricted tool access
  (gptel-agent--task "task-name" ...))
```

### When to Use Skill

```elisp
;; Skill is appropriate when:
(when (or (has-shell-dependencies task)   ; Needs REPL, CLI tools
          (requires-external-api task)     ; Calls external services
          (is-pure-procedure task))         ; No side effects, no deps
  (mementum/skill-invoke "skill-name"))
```

## Common Issues and Debugging Patterns

### Issue 1: Function Not Defined (fboundp returns nil)

**Symptom**: Subagent falls back to local processing, never uses LLM.

**Root Cause Chain**:
```
gptel-tools-agent.el does NOT require gptel-agent
  → gptel-agent--task is never defined
  → (fboundp 'gptel-agent--task) returns nil
  → Falls back to local grading
```

**Debug Flow**:
```elisp
;; Step 1: Check what's loaded
(list :gptel-agent-loaded (featurep 'gptel-agent)
      :gptel-agent--task-fbound (fboundp 'gptel-agent--task)
      :gptel-agent--agents-count (length gptel-agent--agents))
;; → (:gptel-agent-loaded nil 
;;    :gptel-agent--task-fbound nil 
;;    :gptel-agent--agents-count 0)
```

**Fix**:
```elisp
;; In lisp/modules/gptel-tools-agent.el
(require 'gptel-agent)  ; ADD THIS LINE
```

### Issue 2: Variable Shadowing

**Symptom**: `gptel-agent--agents` is nil even after requiring.

**Root Cause**: Redefining with `defvar` shadows the original:

```elisp
;; WRONG: This shadows gptel-agent.el's 
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-dxzHXu.txt. Use Read tool if you need more]...