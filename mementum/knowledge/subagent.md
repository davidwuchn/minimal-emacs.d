---
title: Subagent Architecture and Debugging
status: active
category: knowledge
tags: [subagent, gptel, agent, debugging, emacs-lisp, architecture]
---

# Subagent Architecture and Debugging

Subagents are specialized LLM-powered components that operate with context isolation from the parent agent. They are designed for parallel execution, dedicated tooling, and model selection. This document covers subagent architecture, common pitfalls, and debugging patterns.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      Parent Agent (gptel)                       │
│                         parent-buf                              │
└──────────────────────────────┬──────────────────────────────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
              ▼                ▼                ▼
     ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
     │   Grader     │  │  Reviewer    │  │   Executor   │
     │  Subagent    │  │  Subagent    │  │  Subagent    │
     │ context-isol │  │ context-isol │  │ context-isol │
     │ readonly-tool│  │ readonly-tool│  │ write-tool   │
     │ cheap-model  │  │ cheap-model  │  │ fast-model   │
     └──────────────┘  └──────────────┘  └──────────────┘
```

### Key Components

| Component | File | Purpose |
|-----------|------|---------|
| `gptel-agent--task` | `gptel-agent.el` | Core task execution function |
| `gptel-agent--agents` | `gptel-agent.el` | Agent registry |
| `gptel-tools-agent.el` | Tools module | Provides tool access for subagents |
| `gptel-auto-workflow` | Workflow engine | Manages multi-agent orchestration |

## Decision Matrix: Subagent vs Skill vs Protocol

When deciding how to implement an agent capability, use this matrix:

| Criteria | Protocol | Skill | Subagent |
|----------|----------|-------|----------|
| **External deps** | None | Scripts, REPL, API | API, tools |
| **Context isolation** | No | Shared | Yes |
| **Parallel execution** | No | No | Yes |
| **Dedicated model** | No | No | Yes |
| **State management** | Stateless | Minimal | Stateful |
| **Tool profile** | None | Custom | Limited/readonly |

### When to Use Each

```
Protocols:    mementum/knowledge/{name}-protocol.md
              → Pure procedures, no dependencies

Skills:       assistant/skills/{name}/
              → Has external tools/API, needs REPL

Subagents:    eca/prompts/{name}_agent.md
              → Context isolation, parallel execution, dedicated model
```

### Example: Reviewer Implementation

```json
// eca/config.json
{
  "subagents": {
    "reviewer": {
      "system-prompt": "You are a code reviewer...",
      "model": "gpt-4.4-mini",
      "tools": ["git-diff", "read-only-fs"],
      "context-isolation": true
    }
  }
}
```

**Why Reviewer is a Subagent**:
1. **Context isolation** - Review comments won't pollute parent context
2. **Parallel execution** - Parent spawns reviewer, continues other work
3. **Tool profile** - Only needs readonly tools (git diff, file read)
4. **Dedicated model** - Can use cheaper model for review tasks

## Common Pitfall: Overlay Conflicts

### Problem Description

Overlays from subagent execution appearing in wrong buffers (e.g., `*Messages*`) despite routing fixes.

### Root Cause

**Two conflicting advices on the same function**:

```elisp
;; OLD - Line 461 in gptel-tools-agent.el
(defadvice gptel-agent--task (:override my/gptel-agent--task-override)
  "Old override advice that replaces function entirely"
  (let ((parent-buf (or ad--arg1 (current-buffer))))
    ;; Creates overlays in parent-buf - which may be *Messages*!
    ...))

;; NEW - Line 212 in gptel-auto-workflow-projects.el
(defadvice gptel-agent--task (:around gptel-auto-workflow--advice-task-override)
  "New around advice that wraps original"
  ;; Better behavior but conflicts with old advice
  ...)
```

**Why it fails**:
- `:override` advice completely replaces the original function
- Creates overlays in `parent-buf` 
- If FSM was created in `*Messages*`, overlays appear there
- `:override` and `:around` on same function = unpredictable behavior

### Solution Pattern

```elisp
;; 1. REMOVE the old override advice
;; Delete or comment out the :override advice entirely

;; 2. MERGE caching logic into single :around advice
(defadvice gptel-agent--task (:around gptel-auto-workflow--advice-task-override)
  "Combined advice with caching and workflow routing"
  (let ((cache-key (cons (ad-get-arg 0) (ad-get-arg 1))))
    (if (and gptel-agent--cache-enabled
             (gethash cache-key gptel-agent--task-cache))
        (gethash cache-key gptel-agent--task-cache)
      (setq ad-return-value 
            (let ((result (ad-advice-continue)))
              ;; Post-process result, create overlays in correct buffer
              result)))))

;; 3. Add headless buffer suppression
(defun suppress-buffer-kill-query ()
  "Suppress buffer-modified queries in headless mode."
  (when noninteractive
    (setq kill-buffer-query-functions nil)))
```

### Verification Commands

```bash
# Check for advice conflicts
grep -n "defadvice gptel-agent--task" lisp/modules/*.el

# List all advice on a function
(ad-advice-delete-regexp "gptel-agent--task")
```

## Debug Pattern: Grader Subagent Always Falls Back to Local

### Symptom

Grader subagent always uses local grading instead of LLM-powered grading.

### Debugging Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    TDD Approach                              │
│  1. Write test first → reveals actual behavior               │
│  2. Tests guide fix → don't guess                           │
│  3. Verify fix → tests must pass                            │
└─────────────────────────────────────────────────────────────┘
```

### Root Cause Chain Analysis

```
fboundp → nil → local fallback
    │
    ├── gptel-tools-agent.el does NOT require gptel-agent
    │       │
    │       └── (require 'gptel-agent) MISSING
    │
    ├── gptel-agent--task never defined
    │       │
    │       └── (fboundp 'gptel-agent--task) returns nil
    │
    └── gptel-agent--agents declared nil (shadowing)
            │
            └── (defvar gptel-agent--agents nil) - redundant!
```

### Test-Driven Fix

```elisp
;; tests/test-grader-subagent.el
(ert-deftest test-grader-uses-llm ()
  "Test that grader uses LLM when available."
  (require 'gptel-tools-agent)
  (should (fboundp 'gptel-agent--task))
  (should (> (length gptel-agent--agents) 0)))

(ert-deftest test-grader-model-selection ()
  "Test that grader uses correct model."
  (let ((grader-model (alist-get 'grader gptel-agent--agents)))
    (should (string-match-p "qwen" grader-model))))
```

### Fixes Applied

```elisp
;; lisp/modules/gptel-tools-agent.el - ADD require at top
(require 'gptel-agent)  ; <-- This was missing!
(require 'gptel-core)

;; REMOVE redundant variable declaration
;; (defvar gptel-agent--agents nil)  ; DELETE THIS LINE

;; Fix JSON parser for grader output format
(defun gptel-benchmark-parse-grader-output (json-string)
  "Parse grader JSON with flexible format handling."
  (let ((parsed (json-parse-string json-string :object-type 'alist)))
    (or (alist-get 'score parsed)
        (alist-get 'result parsed)
        (alist-get 'data parsed))))
```

### Verification Output

```
:gptel-agent-loaded t
:gptel-agent--task-fbound t  
:gptel-agent--agents-count 13
:grader-model "qwen3.5-plus"
:executor-model "qwen3.5-plus"
```

### Run Tests

```bash
./scripts/run-tests.sh grader
# or
emacs -batch -l tests/test-grader-subagent.el -f ert-run-tests-batch-and-exit
```

## Implementation Patterns

### Pattern 1: Creating a New Subagent

```elisp
;; Define in eca/prompts/executor_agent.md
# You are an Executor subagent

## Capabilities
- Execute code in sandbox
- Run tests
- Report results

## Tool Profile
- shell-command
- read-file
- write-file (temporary)

## Context
- Isolated from parent
- Uses cheaper model
```

```json
// eca/config.json - Register subagent
{
  "subagents": {
    "executor": {
      "prompt-file": "eca/prompts/executor_agent.md",
      "model": "qwen3.5-plus",
      "timeout": 300,
      "max-tokens": 8192
    }
  }
}
```

### Pattern 2: Spawning Subagent from Parent

```elisp
(defun spawn-grader-subagent (code test-cases)
  "Spawn grader subagent with CODE and TEST-CASES."
  (gptel-agent--task
   (list
    :name "grader"
    :system "You are a code grading assistant..."
    :prompt (format "Grade this code:\n%s\n\nTests:\n%s" 
                    code test-cases)
    :model (or (alist-get 'grader gptel-agent--agents)
               gptel-default-model)
    :context-isolation t)))
```

### Pattern 3: Checking Subagent Availability

```elisp
(defun subagent-available-p (subagent-name)
  "Check if SUBAGENT-NAME is available and loaded."
  (and (fboundp 'gptel-agent--task)
       (alist-get subagent-name gptel-agent--agents)
       t))

(defun get-subagent-model (subagent-name)
  "Get the model configured for SUBAGENT-NAME."
  (or (alist-get 'model 
                (alist-get subagent-name gptel-agent--agents))
      gptel-default-model))
```

## Debugging Checklist

When subagent behavior is unexpected:

- [ ] **Require chain** - Are all required modules loaded?
  ```elisp
  ;; Check: (require 'gptel-agent) present in tools module
  (featurep 'gptel-agent)  ; should be t
  ```

- [ ] **Function defined** - Is `gptel-agent--task` available?
  ```elisp
  (fboundp 'gptel-agent--task)  ; should be t
  ```

- [ ] **Agents registered** - Are subagents in registry?
  ```elisp
  (hash-table-keys gptel-agent--agents)  ; list of available
  ```

- [ ] **Advice conflicts** - Multiple advices on same function?
  ```elisp
  ;; Check for multiple :override/:around advices
  (ad-advice-delete-regexp "gptel-agent--task")
  ```

- [ ] **Buffer routing** - Correct buffer for overlays?
  ```elisp
  (buffer-name (current-buffer))  ; should be workflow buffer
  ```

## Key Files Reference

| File | Purpose | Key Functions |
|------|---------|----------------|
| `lisp/modules/gptel-agent.el` | Core agent implementation | `gptel-agent--task`, `gptel-agent--agents` |
| `lisp/modules/gptel-tools-agent.el` | Tools for subagents | `gptel-tools-agent-execute` |
| `lisp/modules/gptel-auto-workflow-projects.el` | Workflow orchestration | `gptel-auto-workflow--advice-task-override` |
| `lisp/modules/gptel-benchmark-subagent.el` | Grader subagent | JSON parsing, grading logic |
| `tests/test-grader-subagent.el` | Tests | 8 tests for grader behavior |

## Related

- [[gptel-agent-architecture]] - Core agent system
- [[gptel-tools-agent]] - Tool system for agents
- [[gptel-auto-workflow]] - Multi-agent orchestration
- [[skill-vs-subagent]] - When to use each pattern
- [[protocol-development]] - Protocol-based procedures

---

*Last updated: 2026-03-29*
*Status: Active - Maintained*
*Tags: subagent, debugging, emacs-lisp, gptel*