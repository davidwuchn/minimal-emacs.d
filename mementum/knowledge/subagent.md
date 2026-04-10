---
title: Subagent Architecture and Debugging
status: active
category: knowledge
tags: [subagent, emacs, gptel, debugging, eca]
---

# Subagent Architecture and Debugging

This knowledge page covers subagent implementation patterns, debugging techniques, and decision frameworks for when to use subagents in the Emacs AI assistant ecosystem.

## Overview

A **subagent** is a specialized AI agent spawned by a parent agent to handle isolated tasks. Subagents provide:
- **Context isolation** - Subagent context won't pollute parent
- **Parallel execution** - Can run concurrently with parent tasks
- **Tool profile restriction** - Can limit to readonly tools
- **Dedicated model** - Can use cheaper/faster models

## Architecture

### Subagent Types vs Other Patterns

| Pattern | Location | Use Case |
|---------|----------|----------|
| Protocol | `mementum/knowledge/` | Pure procedures, no external dependencies |
| Skill | `assistant/skills/` | Has external tools/API, needs REPL |
| Subagent | `eca/prompts/` | Context isolation, parallel execution |

### Core Files

```
lisp/modules/
├── gptel-tools-agent.el      # Subagent tool integration
├── gptel-agent.el            # Core agent definitions
└── gptel-auto-workflow-projects.el  # Workflow routing
```

---

## When to Use Subagents

### Decision Matrix

Use this matrix to determine whether a task should be implemented as a subagent, skill, or protocol:

| Task Characteristic | Use Subagent | Use Skill | Use Protocol |
|---------------------|--------------|-----------|---------------|
| Context isolation needed | ✓ | | |
| Parallel execution required | ✓ | | |
| Dedicated model desired | ✓ | | |
| Has external API/tools | | ✓ | |
| Has REPL dependencies | | ✓ | |
| Pure procedure, no deps | | | ✓ |
| Shared context with parent | | ✓ | |

### Code Reviewer Example

The code reviewer is a prime candidate for subagent implementation because:

1. **Context isolation** - Review comments shouldn't pollute parent agent's context
2. **Parallel execution** - Parent can spawn reviewer and continue other work
3. **Tool profile** - Reviewer only needs readonly tools (file reading)
4. **Dedicated model** - Can use cheaper model (e.g., gpt-5.4-mini) for review
5. **Already defined** - `eca/config.json` has reviewer subagent configured

---

## Debugging Subagent Issues

### Case Study: Grader Subagent Not Using LLM

**Problem**: Grader subagent always fell back to local grading, never used LLM.

**Symptoms**:
- Grader uses local grading instead of LLM
- `gptel-agent--task` appears undefined

#### Root Cause Chain

```
gptel-tools-agent.el did NOT require gptel-agent
        ↓
gptel-agent--task was never defined (fboundp returned nil)
        ↓
gptel-agent--agents was declared nil (shadowing)
        ↓
(fboundp 'gptel-agent--task) → nil → local grading fallback
```

#### TDD Approach to Fix

1. **Write tests first**: Create test file to reveal actual behavior

```elisp
;; tests/test-grader-subagent.el
(ert-deftest test-grader-subagent-llm-available ()
  "Verify gptel-agent--task is available."
  (should (fboundp 'gptel-agent--task)))

(ert-deftest test-grader-subagent-agents-loaded ()
  "Verify gptel-agent--agents is populated."
  (should (seq-length gptel-agent--agents)))

(ert-deftest test-grader-use-llm ()
  "Verify grader uses LLM when available."
  (should gptel-agent-loaded))
```

2. **Run tests** - Tests reveal actual failure points
3. **Trace the failure** - Follow the root cause chain
4. **Apply fix** - Targeted changes based on test feedback

#### Fixes Applied

**File: `lisp/modules/gptel-tools-agent.el`**

```elisp
;; BEFORE: Missing require
;; (defvar gptel-agent--agents nil)  ; This shadowed the real variable!

;; AFTER: Proper require at top
(require 'gptel-agent)  ; This loads gptel-agent--task definition
```

**File: `lisp/modules/gptel-benchmark-subagent.el`**

```elisp
;; Fixed JSON parser to handle grader output format
(defun gptel-benchmark--parse-grader-output (output)
  "Parse grader OUTPUT into structured result."
  (let ((json-array-type 'list))
    (when (string-match "^{" output)
      (json-read-from-string output))))
```

#### Verification

Run verification commands:

```bash
./scripts/run-tests.sh grader
```

Expected results:

```
:gptel-agent-loaded t
:gptel-agent--task-fbound t  
:gptel-agent--agents-count 13
:grader-model "qwen3.5-plus"
:executor-model "qwen3.5-plus"
```

---

### Case Study: Subagent Overlay Conflict

**Problem**: Subagent overlays appearing in *Messages* buffer despite routing fixes.

**Symptoms**:
- Overlays appear in wrong buffer (*Messages*)
- Executor and Grader overlays visible where they shouldn't
- "Buffer gptel.el modified; kill anyway?" prompts in headless mode

#### Root Cause

**TWO conflicting advices** on `gptel-agent--task`:

1. Old advice (line 461): `my/gptel-agent--task-override` with `:override`
2. New advice (projects.el:212): `gptel-auto-workflow--advice-task-override` with `:around`

The old `:override` advice completely replaces the original function and creates overlays in `parent-buf`, which can be `*Messages*` if the FSM was created there.

#### Solution

1. **Remove old `:override` advice**

```elisp
;; REMOVE THIS from gptel-tools-agent.el:461
(defun my/gptel-agent--task-override (orig-fn &rest args)
  "Override gptel-agent--task to add custom behavior."
  (apply orig-fn args))
```

2. **Merge caching logic into new `:around` advice**

```elisp
;; In gptel-auto-workflow-projects.el:212
(defun gptel-auto-workflow--advice-task-override (orig-fn &rest args)
  "Around advice that adds caching without overriding behavior."
  (let ((cache-key (car args)))
    (or (gethash cache-key gptel-workflow--cache)
        (let ((result (apply orig-fn args)))
          (puthash cache-key result gptel-workflow--cache)
          result))))
```

3. **Add headless mode suppression**

```elisp
;; Suppress kill-buffer query in headless mode
(advice-add 'kill-buffer-query :around
            (lambda (orig-fn &rest args)
              (if gptel-headless-mode
                  (progn
                    (dolist (buf (buffer-list))
                      (when (buffer-modified-p buf)
                        (set-buffer-modified-p nil)))
                    t)
                (apply orig-fn args))))
```

#### Pattern: Advice Type Consistency

> **Key Pattern**: Multiple advices on same function with different types (`:override` vs `:around`) causes unpredictable behavior. Use ONE advice type.

---

## Implementation Patterns

### Pattern 1: Subagent Registration

```elisp
;; Register a subagent in eca/config.json
{
  "subagents": {
    "reviewer": {
      "prompt": "eca/prompts/reviewer_agent.md",
      "model": "gpt-4o-mini",
      "tools": ["read-file", "search"]
    }
  }
}
```

### Pattern 2: Subagent Invocation

```elisp
;; Spawn subagent from parent
(gptel-agent--task
 :name "reviewer"
 :context parent-context
 :task "Review the following code changes..."
 :callback #'handle-review-results)
```

### Pattern 3: Debug Subagent State

```elisp
(defun gptel-debug-subagent-state ()
  "Display subagent state for debugging."
  (message "=== Subagent Debug State ===")
  (message "gptel-agent-loaded: %s" (featurep 'gptel-agent))
  (message "gptel-agent--task fbound: %s" (fboundp 'gptel-agent--task))
  (message "Agents count: %s" (seq-length gptel-agent--agents))
  (message "Active tasks: %s" gptel-agent--active-tasks))
```

Run with `M-x gptel-debug-subagent-state`.

---

## Related

- [ECA Configuration](./eca-config.md) - Subagent configuration
- [Protocol Patterns](./protocol-patterns.md) - When to use protocols
- [Skill Architecture](./skill-architecture.md) - Skill vs subagent decisions
- [gptel-agent Debugging](./gptel-debugging.md) - General agent debugging
- [Workflow Routing](./workflow-routing.md) - Task routing between agents

---

## Quick Reference

### Common Debug Commands

```bash
# Run subagent tests
./scripts/run-tests.sh grader

# Check if agent is loaded
M-x gptel-debug-subagent-state

# Force reload agent module
M-x gptel-agent-reload
```

### Key Variables

| Variable | Purpose |
|----------|---------|
| `gptel-agent--agents` | Registered subagent list |
| `gptel-agent--task` | Main task execution function |
| `gptel-agent--active-tasks` | Currently running tasks |
| `gptel-workflow--cache` | Task result cache |

### File Quick Links

```
lisp/modules/
├── gptel-tools-agent.el           # Line 461 - old advice
├── gptel-agent.el                 # Core agent definitions  
└── gptel-auto-workflow-projects.el # Line 212 - new advice
```