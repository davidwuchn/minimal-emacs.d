---
title: Subagent Architecture and Patterns
status: active
category: architecture
tags: [subagent, gptel, elisp, architecture, debugging, tdd]
---

# Subagent Architecture and Patterns

## Overview

A **subagent** is a specialized agent spawned by a parent agent to handle specific tasks with context isolation, dedicated tooling, and potentially a different model configuration. This knowledge page covers the architecture, decision frameworks, implementation patterns, and common pitfalls for subagent design in the gptel ecosystem.

## When to Use a Subagent

Not every task needs a subagent. Use this decision matrix to choose the right approach:

| Task Characteristic | Subagent | Skill | Protocol |
|---------------------|----------|-------|----------|
| Needs context isolation | ✅ Yes | ❌ No | ❌ No |
| Parallel execution required | ✅ Yes | ❌ No | ❌ No |
| Dedicated/cheaper model available | ✅ Yes | ❌ No | ❌ No |
| Uses external tools/APIs | ⚠️ Maybe | ✅ Yes | ❌ No |
| No external dependencies | ❌ No | ❌ No | ✅ Yes |
| Needs shared context with parent | ❌ No | ✅ Yes | ❌ No |
| Stateful operations | ⚠️ Maybe | ✅ Yes | ❌ No |

### Decision Factors Explained

**Context Isolation**: If the task should not pollute the parent agent's context window, use a subagent. The reviewer example demonstrates this—code review comments should not contaminate the main task context.

**Parallel Execution**: Subagents can run concurrently while the parent continues other work. Skills execute sequentially within the parent's context.

**Dedicated Model**: Subagents can use a cheaper/faster model (e.g., `gpt-4o-mini`) for specific tasks like review or formatting.

**Tool Profile**: Subagents can be configured with a restricted set of readonly tools for security and focus.

## Subagent Structure

```
eca/prompts/{name}_agent.md     # Subagent definition with context, tools, model
lisp/modules/{name}-subagent.el # Implementation (optional custom logic)
tests/test-{name}-subagent.el   # Test suite
```

### Example: Grader Subagent Configuration

```json
{
  "name": "grader",
  "model": "qwen3.5-plus",
  "system-prompt": "You are a code reviewer focused on test quality...",
  "tools": ["readonly-tools"],
  "context-window": 8192
}
```

## Common Patterns

### Pattern 1: TDD Debugging for Subagent Issues

The grader subagent debugging session demonstrates a systematic approach:

```
1. Write failing tests first (reveal actual behavior)
2. Run tests → red (failure expected)
3. Trace root cause
4. Apply fix
5. Run tests → green (verification)
6. Verify with integration command
```

**Key commands**:
```bash
./scripts/run-tests.sh grader
```

### Pattern 2: Subagent Overlay Rendering

When subagents render overlays (e.g., for inline comments), ensure they appear in the correct buffer:

**Problem**: Overlays appearing in `*Messages*` buffer instead of the target file buffer.

**Root Cause**: Multiple conflicting Emacs advices on `gptel-agent--task`:
- Old advice with `:override` (replaces function entirely)
- New advice with `:around` (wraps function)

**Solution Pattern**:
```elisp
;; BAD: Conflicting advice types
(advice-add #'gptel-agent--task :override #'my/old-override)
(advice-add #'gptel-agent--task :around #'gptel-auto-workflow--advice)

;; GOOD: Single advice type
(advice-add #'gptel-agent--task :around #'my/merged-advice)
```

### Pattern 3: Require Chain Verification

Subagent modules must properly declare dependencies:

```elisp
;; CORRECT: gptel-tools-agent.el
(require 'gptel-agent)  ; Required for gptel-agent--task, gptel-agent--agents
(require 'gptel-tools)  ; Additional dependencies

;; INCORRECT: gptel-tools-agent.el
;; (require 'gptel-agent)  ; MISSING - causes fboundp to return nil
(defvar gptel-agent--agents nil)  ; REDUNDANT - shadows the real variable
```

**Verification checklist**:
```elisp
:gptel-agent-loaded t              ; Module loaded
:gptel-agent--task-fbound t        ; Function defined
:gptel-agent--agents-count 13      ; Registry populated
:grader-model "qwen3.5-plus"       ; Model configured
:executor-model "qwen3.5-plus"     ; Executor model configured
```

## Debugging Subagent Issues

### Issue: Subagent Falls Back to Local Processing

**Symptoms**:
- Subagent never uses LLM
- Falls back to local grading/parsing
- `fboundp 'gptel-agent--task` returns `nil`

**Debugging Steps**:
```elisp
;; Step 1: Check if function is defined
(fboundp 'gptel-agent--task)  ; Should return t

;; Step 2: Check if module is loaded
(featurep 'gptel-agent)       ; Should return t

;; Step 3: Check require chain
(require 'gptel-tools-agent)
(require 'gptel-agent)

;; Step 4: Verify agents registry
(length gptel-agent--agents)   ; Should be > 0
```

**Root Cause Chain Analysis**:
1. Module A does NOT require Module B
2. Function `gptel-agent--task` is never defined
3. `gptel-agent--agents` is declared nil (shadows real variable)
4. `(fboundp 'gptel-agent--task)` → `nil` → local fallback

**Fix**: Add missing require and remove redundant declarations.

### Issue: Overlay Conflict

**Symptoms**:
- Overlays in wrong buffer (`*Messages*`)
- "Buffer modified; kill anyway?" prompts in headless mode
- Executor and Grader overlays visible incorrectly

**Fix**:
```elisp
;; Remove old override advice
(advice-remove #'gptel-agent--task #'my/gptel-agent--task-override)

;; Merge logic into new around advice
(advice-add #'gptel-agent--task :around
            (lambda (orig-fun &rest args)
              ;; Merged caching + routing logic
              (let ((target-buf (or (get-buffer "*target*") (current-buffer))))
                (with-current-buffer target-buf
                  (apply orig-fun args)))))
```

## Testing Subagent Behavior

### Test Structure

```elisp
;; tests/test-grader-subagent.el
(require 'ert)
(require 'gptel-tools-agent)
(require 'gptel-benchmark-subagent)

(ert-deftest test-grader-subagent-uses-llm ()
  "Verify grader uses LLM instead of local parsing."
  (let ((gptel-agent--agents '(grader)))
    (should (fboundp 'gptel-agent--task))))

(ert-deftest test-grader-json-parser ()
  "Verify JSON parser handles grader output format."
  (should (equal (parse-grader-output "{\"verdict\": \"pass\"}")
                 '((verdict . "pass")))))
```

### Running Tests

```bash
# Run specific test file
./scripts/run-tests.sh grader

# Run all subagent tests
./scripts/run-tests.sh subagent

# Run with coverage
./scripts/run-coverage.sh tests/test-grader-subagent.el
```

## Best Practices

### 1. Single Responsibility Per Subagent

Each subagent should have one clear purpose:
- ✅ Grader: Evaluates test results
- ✅ Reviewer: Provides code feedback
- ✅ Formatter: Normalizes output
- ❌ Reviewer + Grader + Formatter (too many responsibilities)

### 2. Proper Require Chain

```elisp
;; modules/gptel-tools-agent.el
;;; Code:
(require 'gptel-agent)    ; Always require dependencies
(require 'gptel-tools)    ; Additional tools
(require 'json)           ; Standard library

;; Do NOT redeclare variables from other modules
;; (defvar gptel-agent--agents nil)  ; REMOVE THIS
```

### 3. Model Selection Guidelines

| Task | Recommended Model | Rationale |
|------|------------------|-----------|
| Code Review | `gpt-4o-mini` | Fast, good enough for comments |
| Test Grading | `qwen3.5-plus` | Strong on test logic |
| Code Generation | `gpt-4o` | Best quality |
| Formatting | `gpt-4o-mini` | Fast, deterministic |

### 4. Buffer Management

For subagents that render overlays:
```elisp
(defun my/subagent-render-overlay (content target-buffer)
  "Render CONTENT as overlay in TARGET-BUFFER."
  (with-current-buffer (or target-buffer (current-buffer))
    ;; Ensure we're not in *Messages* or other transient buffers
    (unless (string-match-p "\\`\\*.*\\*\\'" (buffer-name))
      (let ((overlay (make-overlay (point-min) (point-max))))
        (overlay-put overlay 'display content)))))
```

### 5. Advice Pattern: Around Over Override

Always prefer `:around` advice over `:override`:

```elisp
;; PREFERRED: Wraps original function
(advice-add #'gptel-agent--task :around #'my/around-advice)

;; AVOID: Replaces function completely
(advice-add #'gptel-agent--task :override #'my/override-advice)
```

## Architecture Comparison

```
┌─────────────────────────────────────────────────────────────┐
│                      Parent Agent                           │
├─────────────┬─────────────────┬─────────────────────────────┤
│  Protocol   │     Skill       │        Subagent            │
├─────────────┼─────────────────┼─────────────────────────────┤
│ mementum/   │ assistant/      │ eca/prompts/               │
│ knowledge/  │ skills/{name}/   │ {name}_agent.md            │
├─────────────┼─────────────────┼─────────────────────────────┤
│ No deps     │ Scripts, REPL   │ Context isolated           │
│ Stateless   │ Stateful       │ Parallel execution         │
│ Inherit ctx │ Shared ctx      │ Dedicated model possible   │
└─────────────┴─────────────────┴─────────────────────────────┘
```

## Related

- [gptel-agent](./gptel-agent.md) - Core agent infrastructure
- [gptel-tools-agent](./gptel-tools-agent.md) - Tool-based agent module
- [overlay-debugging](./overlay-debugging.md) - Overlay rendering issues
- [advice-patterns](./advice-patterns.md) - Emacs advice best practices
- [tdd-workflow](./tdd-workflow.md) - Test-driven debugging approach
```