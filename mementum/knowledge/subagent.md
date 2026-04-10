---
title: Subagent
status: active
category: knowledge
tags: [subagent, gptel, emacs, debugging, architecture, eca, skill]
---

# Subagent

A subagent is a specialized agent spawned by a parent agent with isolated context, dedicated tooling, and often a different model configuration. Subagents provide context isolation, parallel execution capability, and task-specific optimization within the Emacs gptel ecosystem.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Parent Agent                              │
│  (main conversation, full context, all tools)                │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ spawns
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Subagent                                  │
│  - Isolated context (doesn't pollute parent)                 │
│  - Limited tool profile (readonly for reviewers)            │
│  - Dedicated model (cheaper/faster option)                  │
│  - Parallel execution capability                            │
└─────────────────────────────────────────────────────────────┘
```

## Decision Matrix: When to Use Subagents

Choose between subagent, skill, or protocol based on task characteristics:

| Task Type | Use | Why |
|-----------|-----|-----|
| Pure procedure (no deps) | Protocol → `mementum/knowledge/` | No external dependencies |
| Has external tools/API | Skill → `assistant/skills/` | Needs scripts, REPL, API |
| Context isolation needed | Subagent → `eca/prompts/` | Won't pollute parent |
| Parallel execution | Subagent | Can run concurrently |
| Dedicated model | Subagent | Cheaper/faster model option |
| Shared context | Skill | Uses parent's context |

### Directory Structure

```
Protocols:    mementum/knowledge/{name}-protocol.md
Tool Skills:  assistant/skills/{name}/ (with REPL/API deps)
Subagents:    eca/prompts/{name}_agent.md (context isolation)
```

## Subagent Configuration

### Defining a Subagent in eca/config.json

```json
{
  "subagents": {
    "reviewer": {
      "prompt_file": "eca/prompts/reviewer_agent.md",
      "model": "gpt-4.4-mini",
      "tools": ["read-only-files", "grep", "diff"],
      "isolation": "strict"
    },
    "grader": {
      "prompt_file": "eca/prompts/grader_agent.md",
      "model": "qwen3.5-plus",
      "tools": ["evaluate-code"],
      "isolation": "moderate"
    }
  }
}
```

### Subagent Registration Pattern

```elisp
;; In lisp/modules/gptel-tools-agent.el
(require 'gptel-agent)  ; Required for agent infrastructure

(defvar gptel-agent--agents
  '(("reviewer" . reviewer-definition)
    ("grader" . grader-definition)))

(defun spawn-subagent (name &optional model tools)
  "Spawn NAME subagent with optional MODEL and TOOLS."
  (let ((agent-config (assoc-default name gptel-agent--agents)))
    (gptel-agent--task model tools agent-config)))
```

## Debugging Subagent Issues

### Case Study: Grader Subagent Always Fell Back to Local Grading

**Problem**: Grader subagent never used LLM, always defaulted to local grading.

**Root Cause Chain**:
```
gptel-tools-agent.el did NOT require gptel-agent
         │
         ▼
gptel-agent--task was never defined (fboundp returned nil)
         │
         ▼
gptel-agent--agents was declared nil (shadowing)
         │
         ▼
(fboundp 'gptel-agent--task) → nil → local grading fallback
```

### TDD Approach to Fix

**Step 1**: Write tests first to reveal actual behavior

```elisp
;; tests/test-grader-subagent.el
(ert-deftest test-grader-subagent-loaded ()
  "Test that gptel-agent is loaded."
  (should (featurep 'gptel-agent)))

(ert-deftest test-grader-agent-task-fbound ()
  "Test that gptel-agent--task is defined."
  (should (fboundp 'gptel-agent--task)))

(ert-deftest test-grader-agents-count ()
  "Test that agents are registered."
  (should (> (length gptel-agent--agents) 0)))
```

**Step 2**: Run tests to confirm failure

```bash
./scripts/run-tests.sh grader
;; Expected: red (tests fail)
```

**Step 3**: Fix based on test feedback

```elisp
;; lisp/modules/gptel-tools-agent.el - FIX APPLIED

;; 1. Add require at TOP of file (not inside function)
(require 'gptel-agent)

;; 2. Remove redundant defvar that shadows the agent
;; REMOVED: (defvar gptel-agent--agents nil)

;; 3. Fix JSON parser for grader output format
(defun gptel-benchmark--parse-grader-output (output)
  "Parse grader OUTPUT into structured result."
  (let* ((json (json-read-string output))
         (score (alist-get 'score json))
         (feedback (alist-get 'feedback json)))
    (list :score score :feedback feedback)))
```

**Step 4**: Verify fix

```elisp
;; Verification results
(list
 :gptel-agent-loaded t
 :gptel-agent--task-fbound t
 :gptel-agent--agents-count 13
 :grader-model "qwen3.5-plus"
 :executor-model "qwen3.5-plus")
```

### Key Files in Grader Fix

| File | Change |
|------|--------|
| `lisp/modules/gptel-tools-agent.el` | Added `(require 'gptel-agent)` |
| `lisp/modules/gptel-benchmark-subagent.el` | Fixed JSON parser |
| `tests/test-grader-subagent.el` | 8 tests, all pass |

## Common Pitfalls

### Pitfall 1: Conflicting Emacs Advice

**Problem**: Subagent overlays appearing in wrong buffer (e.g., `*Messages*`) despite routing fixes.

**Root Cause**: TWO conflicting advices on `gptel-agent--task`:

```elisp
;; Old advice - :override completely replaces function
(advice-add #'gptel-agent--task
            :override
            #'my/gptel-agent--task-override)

;; New advice - :around wraps function
(advice-add #'gptel-agent--task
            :around
            #'gptel-auto-workflow--advice-task-override)
```

**Symptoms**:
- Overlays appear in `*Messages*` buffer
- Executor and Grader overlays visible in wrong buffer
- "Buffer gptel.el modified; kill anyway?" prompts in headless mode

**Solution**:

```elisp
;; 1. Remove old :override advice
(advice-remove #'gptel-agent--task
               #'my/gptel-agent--task-override)

;; 2. Merge caching logic into :around advice
(advice-add #'gptel-agent--task
            :around
            (defun gptel-auto-workflow--advice-task-override
                (orig-fun &rest args)
              "Merge caching into single :around advice."
              (let ((cache-key (car args)))
                (or (gethash cache-key *agent-cache*)
                    (let ((result (apply orig-fun args)))
                      (puthash cache-key result *agent-cache*)
                      result)))))

;; 3. Suppress kill-buffer query in headless mode
(when noninteractive
  (setq-local kill-buffer-query-functions nil))
```

**Files**:
- `lisp/modules/gptel-tools-agent.el:461` - old advice registration
- `lisp/modules/gptel-auto-workflow-projects.el:212` - new advice

### Pitfall 2: Missing Require Statements

Always ensure required features are loaded at the top of files:

```elisp
;; CORRECT - require at top
(require 'gptel-agent)
(require 'gptel-tools)

;; WRONG - require inside function (lazy load, but breaks fboundp checks)
(defun some-function ()
  (require 'gptel-agent)  ; Too late if checked earlier
  ...)
```

### Pitfall 3: Variable Shadowing

Avoid redundant `defvar` that shadow existing variables:

```elisp
;; WRONG - shadows gptel-agent--agents
(defvar gptel-agent--agents nil)

;; CORRECT - use setq or modify existing
(setq gptel-agent--agents (append gptel-agent--agents '(...)))
```

## Subagent Patterns

### Pattern 1: Context Isolation

Use when review shouldn't pollute parent context:

```elisp
(defun spawn-reviewer (&optional buffer)
  "Spawn reviewer subagent with isolated context."
  (let ((reviewer-buf (generate-new-buffer " *reviewer*")))
    (with-current-buffer reviewer-buf
      (gptel-agent--task
       "gpt-4.4-mini"
       '("read-only-files" "grep" "diff")
       (list :context buffer)))))
```

### Pattern 2: Parallel Execution

```elisp
;; Spawn multiple subagents concurrently
(make-thread
 (lambda () (spawn-subagent "reviewer")))
(make-thread
 (lambda () (spawn-subagent "grader")))
```

### Pattern 3: Dedicated Model Selection

```elisp
(defun select-subagent-model (task-type)
  "Select optimal model for TASK-TYPE."
  (pcase task-type
    ('review "gpt-4.4-mini")    ; Cheaper for readonly
    ('grader "qwen3.5-plus")    ; Strong for evaluation
    ('coder  "gpt-4o")          ; Full power for editing
    (_       "gpt-4.4-mini")))
```

## Testing Subagents

### Basic Test Suite Template

```elisp
;; tests/test-subagent.el
(ert-deftest test-subagent-spawn ()
  "Test subagent spawning returns valid buffer."
  (let ((subagent-buf (spawn-subagent "reviewer")))
    (should (buffer-live-p subagent-buf))))

(ert-deftest test-subagent-context-isolation ()
  "Test subagent doesn't share parent context."
  (let ((parent-ctx (buffer-string))
        (subagent-buf (spawn-subagent "reviewer")))
    (with-current-buffer subagent-buf
      (should-not (string-match parent-ctx (buffer-string))))))

(ert-deftest test-subagent-model-selection ()
  "Test model selection based on task type."
  (should (string= (select-subagent-model 'reviewer) "gpt-4.4-mini"))
  (should (string= (select-subagent-model 'grader) "qwen3.5-plus")))
```

### Running Tests

```bash
# Run specific subagent tests
./scripts/run-tests.sh grader

# Run all subagent-related tests
./scripts/run-tests.sh subagent

# Run with verbose output
./scripts/run-tests.sh subagent --verbose
```

## Related Topics

- [Grader Subagent](./grader-subagent.md) - Code evaluation subagent
- [Reviewer Agent](./reviewer-agent.md) - Code review subagent
- [gptel-agent](./gptel-agent.md) - Core agent infrastructure
- [ECA Configuration](./eca-config.md) - Subagent definitions in config
- [Emacs Advice](./emacs-advice.md) - Understanding :override vs :around
- [Skill vs Protocol](./skill-vs-protocol.md) - Task type decision guide
- [TDD Debugging](./tdd-debugging.md) - Test-driven debugging methodology
- [Overlay Management](./overlay-management.md) - Buffer overlay handling

---

*Last updated: 2026-03-29 | Status: active | Related: gptel, eca, debugging*