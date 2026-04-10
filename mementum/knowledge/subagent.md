---
title: Subagent Architecture and Debugging
status: active
category: knowledge
tags: [subagent, gptel, emacs, debugging, architecture]
---

# Subagent Architecture and Debugging

This document covers subagent implementation patterns, debugging techniques, and the decision framework for when to use subagents versus other patterns in the GPTel/ECA ecosystem.

## 1. Overview

Subagents are specialized AI agents spawned within the GPTel framework to handle specific tasks with isolated context, dedicated tool profiles, and optional dedicated models. They enable parallel execution and context isolation while maintaining shared communication channels with the parent agent.

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Parent Agent** | The main agent that spawns subagents |
| **Subagent** | A specialized agent with defined role and tools |
| **Context Isolation** | Subagent context doesn't pollute parent |
| **Tool Profile** | Subset of tools available to subagent |
| **Dedicated Model** | Optional cheaper/faster model for subagent |

---

## 2. Subagent vs Skill Decision Framework

When implementing a new agent capability, choose between Protocol, Skill, or Subagent based on the following decision matrix:

### Decision Matrix

| Task Type | Use | Why |
|-----------|-----|-----|
| Pure procedure (no deps) | Protocol → `mementum/knowledge/` | No external dependencies |
| Has external tools/API | Skill → `assistant/skills/` | Needs scripts, REPL, API |
| Context isolation needed | Subagent → `eca/prompts/` | Won't pollute parent |
| Parallel execution | Subagent | Can run concurrently |
| Dedicated model | Subagent | Cheaper/faster model option |
| Shared context | Skill | Uses parent's context |

### Why Use Subagents

The **code reviewer** exemplifies an ideal subagent use case:

```json
// eca/config.json
{
  "subagents": {
    "reviewer": {
      "model": "gpt-4.1-mini",
      "system-prompt": "You are a code reviewer...",
      "tools": ["diff", "grep", "compile"]
    }
  }
}
```

Benefits:
1. **Context isolation** - Review comments won't pollute parent agent's context
2. **Parallel execution** - Parent spawns reviewer and continues other work
3. **Tool profile** - Reviewer only needs readonly tools (diff, grep)
4. **Dedicated model** - Use cheaper model (gpt-4.1-mini) for review

### Structure Organization

```
Protocols:    mementum/knowledge/{name}-protocol.md
Tool Skills:  assistant/skills/{name}/ (with REPL/API deps)
Subagents:    eca/prompts/{name}_agent.md (context isolation)
```

---

## 3. Debugging Subagent Issues

### Common Problem: Subagent Falls Back to Local Execution

When a subagent always falls back to local execution instead of using LLM, follow this debugging chain:

#### Debugging Commands

```elisp
;; Check if agent function is defined
(fboundp 'gptel-agent--task)

;; Check agent configuration
(gptel-agent--task "test-prompt")

;; Verify loaded modules
(list (featurep 'gptel-agent)
      (featurep 'gptel-tools-agent))

;; Inspect agent registry
(gptel-agent--agents)
```

#### Expected Values After Fix

```
:gptel-agent-loaded t
:gptel-agent--task-fbound t  
:gptel-agent--agents-count 13
:grader-model "qwen3.5-plus"
:executor-model "qwen3.5-plus"
```

### Root Cause Pattern

The grader subagent issue revealed a common Emacs Lisp pattern error:

```elisp
;; WRONG: File doesn't require the defining module
(require 'gptel-tools-agent)  ; This loads tools but NOT agent

;; RIGHT: Must explicitly require the defining module
(require 'gptel-agent)        ; This defines gptel-agent--task
(require 'gptel-tools-agent)  ; Tools depend on agent being loaded
```

#### Root Cause Chain

1. `gptel-tools-agent.el` did NOT require `gptel-agent`
2. `gptel-agent--task` was never defined (fboundp returned nil)
3. `gptel-agent--agents` was declared nil (shadowing)
4. `(fboundp 'gptel-agent--task)` → nil → local grading fallback

### TDD Debugging Approach

```bash
# Run tests to reveal actual behavior
./scripts/run-tests.sh grader

# Test output shows: 8 tests, all pass
```

```elisp
;; Write test first to verify expected behavior
(ert-deftest test-grader-subagent-uses-llm ()
  (should (gptel-agent--task "Grade this code"))
  (should (eq (gptel-agent--get-subagent 'grader) 'llm-mode)))
```

### Fixes Applied

1. **Add require statement** at top of `gptel-tools-agent.el`:

```elisp
;;; gptel-tools-agent.el --- Tools for GPTel agents

(require 'gptel-agent)  ; MUST come before using gptel-agent--task
(require 'gptel-core)
(require 'json)
;; ... rest of code
```

2. **Remove redundant variable declarations**:

```elisp
;; WRONG: This shadows the agent registry
(defvar gptel-agent--agents nil)

;; RIGHT: Just use the existing registry
;; Remove this line entirely
```

3. **Fix JSON parser** for grader output format:

```elisp
(defun gptel-benchmark--parse-grader-output (json-string)
  "Parse JSON output from grader subagent."
  (when (string-match-p "```json" json-string)
    (setq json-string 
          (car (last (split-string json-string "```json")))))
  (json-read-from-string json-string))
```

---

## 4. Overlay Conflict Pattern

### Problem Description

Subagent overlays appearing in wrong buffers (e.g., *Messages* buffer) despite routing fixes.

### Root Cause

**TWO conflicting advices** on the same function with different advice types:

```elisp
;; OLD advice (line 461) - :override completely replaces function
(defadvice gptel-agent--task (my/gptel-agent--task-override
                               :override)
  "Override task execution for caching."
  ;; Creates overlays in parent-buffer
  (my/executor-run-with-cache ad-arg))

;; NEW advice (projects.el:212) - :around wraps original
(defadvice gptel-agent--task (gptel-auto-workflow--advice-task-override
                               :around)
  "Wrap task with workflow logic."
  ;; May reference wrong buffer for overlays
  (let ((result ad-arg))
    (gptel-workflow--process result)))
```

### Symptoms

- Overlays visible in *Messages* buffer after "fixes"
- Executor and Grader overlays in wrong buffer
- "Buffer gptel.el modified; kill anyway?" prompts in headless mode
- Inconsistent behavior between runs

### Solution Pattern

```elisp
;; REMOVE the old :override advice entirely
;; (defadvice gptel-agent--task ... :override)  ; DELETE THIS

;; KEEP only the :around advice, merge caching logic
(defadvice gptel-agent--task (gptel-auto-workflow--advice-task-override
                               :around)
  "Wrap task with workflow and caching logic."
  (let ((cache-key (gptel-workflow--make-cache-key ad-arg)))
    (or (gethash cache-key gptel-workflow--cache)
        (puthash cache-key 
                 (funcall ad-subr-1 ad-arg)
                 gptel-workflow--cache))))

;; Add buffer suppression for headless mode
(setq kill-buffer-query-functions
      (remq 'askWhetherToSaveBufs
            kill-buffer-query-functions))
```

### Key Files

| File | Line | Issue |
|------|------|-------|
| `lisp/modules/gptel-tools-agent.el` | 461 | Old advice registration |
| `lisp/modules/gptel-auto-workflow-projects.el` | 212 | New advice |

### Pattern: Single Advice Type

**Rule**: Use ONE advice type per function. Multiple advices with different types (`:override` vs `:around`) cause unpredictable behavior.

```elisp
;; Good: Single advice
(defadvice function-name (my-advice :around)
  "Docstring."
  (let ((result (funcall ad-subr-1 ad-arg)))
    ;; Post-processing
    result))

;; Bad: Multiple advices on same function
(defadvice function-name (advice1 :override) ...)  ; Remove
(defadvice function-name (advice2 :around) ...)    ; Keep only one
```

---

## 5. Verification and Testing

### Running Subagent Tests

```bash
# Run grader subagent tests
./scripts/run-tests.sh grader

# Run all subagent tests
./scripts/run-tests.sh subagent

# Run in debug mode
./scripts/run-tests.sh grader --debug
```

### Test File Structure

```elisp
;;; tests/test-grader-subagent.el --- Grader subagent tests

(ert-deftest test-grader-subagent-llm-mode ()
  "Verify grader uses LLM instead of local fallback."
  (let ((gptel-agent--agents '(grader)))
    (should (gptel-agent--task "Grade this code"))))

(ert-deftest test-grader-subagent-json-parse ()
  "Verify JSON parser handles grader output."
  (should (gptel-benchmark--parse-grader-output "{\"score\": 85}")))

(ert-deftest test-grader-subagent-model-selection ()
  "Verify dedicated model is selected for grader."
  (should (string= (gptel-agent--get-model 'grader) "qwen3.5-plus")))
```

---

## 6. Actionable Patterns

### Pattern 1: Create New Subagent

```bash
# 1. Create subagent prompt file
touch eca/prompts/reviewer_agent.md

# 2. Add to eca/config.json
{
  "subagents": {
    "reviewer": {
      "model": "gpt-4.1-mini",
      "system-prompt-file": "eca/prompts/reviewer_agent.md",
      "tools": ["diff", "grep", "compile", "eshell"]
    }
  }
}

# 3. Register in gptel-agent.el
(push '(reviewer . reviewer-agent) gptel-agent--agents)
```

### Pattern 2: Debug Subagent Not Loading

```elisp
;; Step 1: Check feature loading
M-x esql RET
(featurep 'gptel-agent) RET  ; Should be t

;; Step 2: Check function definition
(fboundp 'gptel-agent--task) RET  ; Should be t

;; Step 3: Check agent registry
(gptel-agent--agents) RET  ; Should show your subagent

;; Step 4: Check require chain
(require 'gptel-agent)
(require 'gptel-tools-agent)
```

### Pattern 3: Fix Overlay in Wrong Buffer

```elisp
;; Ensure overlays go to correct buffer
(defun gptel-subagent--ensure-buffer (buf-name)
  "Ensure BUF-NAME exists and is current."
  (or (get-buffer buf-name)
      (generate-new-buffer buf-name)))

;; In advice, bind buffer explicitly
(defadvice gptel-agent--task (my/subagent-buffer-fix :around)
  "Ensure subagent uses correct buffer."
  (let ((gptel-parent-buffer (gptel-subagent--ensure-buffer 
                               "*gptel-subagent*")))
    ad-do-it))
```

---

## 7. Best Practices

### Do

- ✅ Use `require` statements to ensure dependency loading
- ✅ Write tests before fixing bugs (TDD approach)
- ✅ Use `:around` advice instead of `:override`
- ✅ Keep subagent context isolated from parent
- ✅ Use dedicated cheaper models for simple subagents
- ✅ Verify with `(fboundp 'function-name)` checks

### Don't

- ❌ Don't use `:override` advice - it breaks original function
- ❌ Don't declare `(defvar gptel-agent--agents nil)` - it shadows registry
- ❌ Don't assume modules load each other - always explicit `require`
- ❌ Don't spawn subagents in temp buffers - use named buffers
- ❌ Don't use same model for subagent as parent - defeats optimization

---

## Related

- [GPTel Agent Architecture](./gptel-agent-architecture.md)
- [Tool Skills Implementation](./tool-skills.md)
- [Protocol Definitions](./protocol-definition.md)
- [ECA Configuration](./eca-configuration.md)
- [Advice and Hooks](./advice-hooks.md)
- [TDD in Emacs](./tdd-emacs.md)

---

*Generated from debug session 2026-03-29, reviewer decision matrix, and grader subagent fixes.*