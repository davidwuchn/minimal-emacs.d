---
title: Subagent
status: active
category: knowledge
tags: [subagent, emacs, gptel, agent, debugging, architecture]
---

# Subagent

A subagent is a specialized LLM-powered component spawned by a parent agent to handle specific tasks with context isolation, dedicated tooling, and optional separate model routing. This page covers subagent implementation, debugging, and architectural patterns in the gptel/ECA framework.

## Architecture Overview

Subagents in this system are built on `gptel-agent` and communicate via a state machine that routes responses between parent and child agents.

```
┌─────────────────────────────────────────────────────────────┐
│                        Parent Agent                         │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐      │
│  │   Planner   │───▶│  Executor  │───▶│   Grader    │      │
│  │  (Orchestr) │    │  (Worker)  │    │ (Validator) │      │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘      │
└─────────┼──────────────────┼──────────────────┼────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
    ┌──────────┐     ┌──────────┐      ┌──────────┐
    │ Subagent  │     │ Subagent  │      │ Subagent  │
    │  (Plan)   │     │  (Exec)   │      │  (Judge)  │
    └──────────┘     └──────────┘      └──────────┘
```

## Implementation

### Core Requirements

A subagent module must require the base agent package:

```elisp
;;; lisp/modules/gptel-tools-agent.el -*- lexical-binding: t; -*-

(require 'gptel-agent)  ; CRITICAL: Without this, subagent functions are undefined
(require 'gptel-benchmark-subagent)

(defcustom gptel-tools-agent-model nil
  "Model for tool-using subagent."
  :group 'gptel
  :type '(string :tag "Model"))
```

### Subagent Definition Pattern

```elisp
(defvar gptel-agent--agents nil
  "Alist of available subagents.")

(defun gptel-agent--task (agent-name prompt &optional callback)
  "Spawn AGENT-NAME with PROMPT.
CALLBACK is invoked with (ok . result) when complete."
  (let ((agent-config (cdr (assoc agent-name gptel-agent--agents))))
    (gptel-agent--run-task agent-config prompt callback)))
```

## Debugging Subagent Issues

### The Grader Subagent Debug Session

**Problem**: Grader subagent always fell back to local grading, never used LLM.

**Root Cause Chain**:
1. `gptel-tools-agent.el` did NOT require `gptel-agent`
2. `gptel-agent--task` was never defined (`fboundp` returned nil)
3. `gptel-agent--agents` was declared nil (shadowing)
4. `(fboundp 'gptel-agent--task)` → nil → local grading fallback

**TDD Approach**:
1. Wrote tests first: `tests/test-grader-subagent.el`
2. Tests revealed actual behavior
3. Tests guided fix
4. Tests verify fix works

**Fixes Applied**:
```elisp
;; 1. Add require at top of gptel-tools-agent.el
(require 'gptel-agent)

;; 2. Remove redundant variable declaration that shadows
;; BEFORE: (defvar gptel-agent--agents nil)  ; BAD - shadows the real one
;; AFTER: No declaration needed - use the one from gptel-agent.el

;; 3. Fix JSON parser for grader output
(defun gptel-benchmark--parse-grader-output (output)
  (let ((json-object-type 'plist))
    (json-read-from-string output)))
```

**Verification**:
```
:gptel-agent-loaded t
:gptel-agent--task-fbound t  
:gptel-agent--agents-count 13
:grader-model "qwen3.5-plus"
:executor-model "qwen3.5-plus"
```

### Running Tests

```bash
# Run grader subagent tests
./scripts/run-tests.sh grader

# Or from Emacs
M-x elpy-test-module RET grader-subagent
```

## Decision Matrix: Subagent vs Skill vs Protocol

When deciding whether to implement a capability as a subagent, skill, or protocol:

| Task Type | Implementation | Why |
|-----------|----------------|-----|
| Pure procedure (no deps) | Protocol → `mementum/knowledge/` | No external dependencies |
| Has external tools/API | Skill → `assistant/skills/` | Needs scripts, REPL, API |
| Context isolation needed | Subagent → `eca/prompts/` | Won't pollute parent |
| Parallel execution | Subagent | Can run concurrently |
| Dedicated model | Subagent | Cheaper/faster model option |
| Shared context | Skill | Uses parent's context |

### Code Reviewer → Subagent

The code reviewer is better as a subagent than a skill:

| Factor | Subagent Benefit |
|--------|-----------------|
| Context isolation | Review shouldn't pollute parent agent's context |
| Parallel execution | Parent can spawn reviewer and continue other work |
| Tool profile | Reviewer only needs readonly tools |
| Dedicated model | Can use cheaper model (gpt-5.4-mini) for review |
| Already defined | `eca/config.json` has reviewer subagent |

**Structure**:
```
Protocols:    mementum/knowledge/{name}-protocol.md
Tool Skills:  assistant/skills/{name}/ (with REPL/API deps)
Subagents:    eca/prompts/{name}_agent.md (context isolation)
```

## Common Pitfall: Subagent Overlay Conflicts

### Problem

Subagent overlays appearing in *Messages* buffer despite routing fixes.

### Root Cause

**TWO conflicting advices** on `gptel-agent--task`:

1. `my/gptel-agent--task-override` with `:override` (old, line 461)
2. `gptel-auto-workflow--advice-task-override` with `:around` (new, in projects.el)

The old `:override` advice completely replaces the original function and creates overlays in `parent-buf`, which can be *Messages* if the FSM was created there.

**Symptoms**:
- Overlays still appear in *Messages* after "fixes"
- Executor and Grader overlays visible in wrong buffer
- "Buffer gptel.el modified; kill anyway?" prompts in headless mode

### Solution

```elisp
;; BEFORE: Conflicting advice types
(defun my/gptel-agent--task-override (orig-fn &rest args)
  "Old override advice - COMPLETELY REPLACES function."
  (let ((gptel-agent--task-cache (make-hash-table)))
    (apply orig-fn args)))

;; AFTER: Single advice with merged logic
(defun gptel-auto-workflow--advice-task-override (orig-fn agent-name prompt &optional callback)
  "Around advice - wraps and enhances original."
  (let ((cached-result (gethash agent-name gptel-agent--task-cache)))
    (or cached-result
        (prog1 (funcall orig-fn agent-name prompt callback)
          (puthash agent-name (current-buffer) gptel-agent--task-cache)))))
```

**Key Pattern**: Use ONE advice type. Multiple advices on same function with different types (`:override` vs `:around`) causes unpredictable behavior.

### Files to Check

| File | Line | Issue |
|------|------|-------|
| `lisp/modules/gptel-tools-agent.el` | 461 | Old advice registration |
| `lisp/modules/gptel-auto-workflow-projects.el` | 212 | New advice |

## Actionable Patterns

### Pattern 1: Test-First Debugging

```elisp
;; tests/test-grader-subagent.el
(ert-deftest test-grader-uses-llm ()
  "Verify grader subagent actually calls LLM."
  (let ((gptel-agent-loaded nil))
    (require 'gptel-tools-agent)
    (should (fboundp 'gptel-agent--task))))

(ert-deftest test-grader-model-set ()
  "Verify grader gets correct model."
  (let ((gptel-tools-agent-model "qwen3.5-plus"))
    (should (string= gptel-tools-agent-model
                     (gptel-agent--get-model-for "grader")))))
```

### Pattern 2: Context Isolation

```elisp
(defun spawn-reviewer-subagent (code-to-review)
  "Spawn reviewer with isolated context."
  (let ((gptel-agent-parent-buffer nil)  ; Force new buffer
        (gptel-agent-isolate-context t))
    (gptel-agent--task "reviewer"
                       (concat "Review this code:\n" code-to-review)
                       #'review-callback)))
```

### Pattern 3: Model Routing

```elisp
(defvar gptel-agent-model-routing
  '(("reviewer" . "gpt-4o-mini")      ; Cheap for simple review
    ("planner" . "gpt-4o")              ; Smart for planning
    ("executor" . "qwen3.5-plus")       ; Fast for execution)
  "Model routing table for subagents.")

(defun gptel-agent--route-model (agent-name)
  "Route to appropriate model for AGENT-NAME."
  (or (cdr (assoc agent-name gptel-agent-model-routing))
      (gptel-default-model)))
```

## Quick Reference

### Commands

```elisp
;; Check if subagent system is loaded
M-x gptel-agent--status

;; Spawn a subagent manually
M-x gptel-agent--task RET reviewer RET "Review this code..."

;; View active subagents
M-x gptel-agent--list-active
```

### Key Variables

| Variable | Purpose |
|----------|----------|
| `gptel-agent--agents` | Registry of available subagents |
| `gptel-agent-parent-buffer` | Buffer for parent context |
| `gptel-agent-isolate-context` | Whether to isolate context |
| `gptel-agent-model-routing` | Model selection per subagent |

### Debugging Checklist

- [ ] Is `gptel-agent` required? (`(require 'gptel-agent)`)
- [ ] Is `fboundp` true for `gptel-agent--task`?
- [ ] Are there conflicting advice definitions?
- [ ] Is the parent buffer correct?
- [ ] Does the model support tool use?

## Related

- [gptel-agent](gptel-agent) - Base agent implementation
- [ECA Configuration](eca-configuration) - Subagent registry
- [Grader Subagent](grader-subagent) - Specific subagent implementation
- [Testing Strategy](testing-strategy) - TDD approach for agents
- [Protocols](protocols) - Alternative to subagents for simple tasks
- [Skills](skills) - Alternative to subagents for tool-heavy tasks
- [Debugging Emacs](debugging-emacs) - General Emacs debugging patterns

---

*Last updated: 2026-03-29*
*Category: infrastructure / agent-framework*