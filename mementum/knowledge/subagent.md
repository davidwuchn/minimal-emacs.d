---
title: Subagent
status: active
category: knowledge
tags: [gptel, subagent, agent, debug, emacs, lisp, architecture]
---

# Subagent

A subagent is a specialized autonomous entity spawned within the gptel framework to handle specific tasks with dedicated context, tools, and optionally a different model than the parent agent. Subagents provide context isolation, parallel execution capability, and tool profile customization.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Parent Agent (gptel)                      │
├─────────────────────────────────────────────────────────────┤
│  Context: Full conversation history                         │
│  Tools: Full tool suite                                      │
│  Model: Primary model (e.g., gpt-4o)                         │
└─────────────────────────────────────────────────────────────┘
          │
          │ (spawns)
          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Subagent (specialized)                    │
├─────────────────────────────────────────────────────────────┤
│  Context: Isolated from parent                               │
│  Tools: Subset (readonly, domain-specific)                   │
│  Model: Dedicated (cheaper/faster, e.g., gpt-4o-mini)        │
│  Prompt: eca/prompts/{name}_agent.md                        │
└─────────────────────────────────────────────────────────────┘
```

## Key Concepts

### Context Isolation

Subagents maintain separate context from the parent agent. This prevents:
- Polluting parent context with intermediate reasoning
- Token budget contamination
- Unintended tool access

### Tool Profile Customization

Each subagent can have a restricted tool set:

```elisp
(defcustom gptel-agent--tools '()
  "Tool definitions available to the current agent.
Each element is a list: (name docstring function)")
```

Example: Code reviewer subagent only needs readonly tools (no file creation, no shell commands).

### Dedicated Model Selection

Subagents can use cheaper/faster models for specialized tasks:

```elisp
(defcustom gptel-agent-model "qwen3.5-plus"
  "Model for the executor subagent.")
```

## Debugging Subagents

### Common Failure Pattern: Missing Require

**Symptoms**: Subagent falls back to local behavior instead of using LLM.

**Debug Flow**:

```elisp
;; Step 1: Check if agent function is defined
(fboundp 'gptel-agent--task)  ; Should return t

;; Step 2: Check agent list
(length gptel-agent--agents)  ; Should be > 0

;; Step 3: Verify agent is loaded
(alist-get :gptel-agent-loaded agent-info)
```

**Root Cause Chain**:
1. Module A does NOT require Module B
2. `gptel-agent--task` is never defined
3. Variable `gptel-agent--agents` is nil (shadowed)
4. `(fboundp 'gptel-agent--task)` returns nil
5. Falls back to local behavior

**Fix Example** (from grader-subagent debug):

```elisp
;; BEFORE (gptel-tools-agent.el)
;; Missing require statement

;; AFTER
(require 'gptel-agent)  ; Added at top of file
```

### Conflict Pattern: Multiple Advices

**Symptoms**: 
- Overlays appearing in wrong buffer (*Messages* buffer)
- "Buffer modified; kill anyway?" prompts in headless mode
- Unexpected behavior after "fixes"

**Root Cause**: Two conflicting advices on `gptel-agent--task`:

```elisp
;; Old advice (line 461) - :override completely replaces function
(advice-add #'gptel-agent--task :override
            #'my/gptel-agent--task-override)

;; New advice - :around wraps original
(advice-add #'gptel-agent--task :around
            #'gptel-auto-workflow--advice-task-override)
```

**Problem**: `:override` advice completely replaces the original function. If created in `parent-buf` (which might be *Messages*), overlays appear there.

**Solution**:

```elisp
;; 1. Remove old :override advice
(advice-remove #'gptel-agent--task
               #'my/gptel-agent--task-override)

;; 2. Merge caching logic into single :around advice
(advice-add #'gptel-agent--task :around
            #'gptel-auto-workflow--advice-task-override)

;; 3. Suppress kill-buffer query in headless mode
(setq kill-buffer-query-functions
      (remq #'process-kill-buffer-query-function
            kill-buffer-query-functions))
```

### Verification Commands

```elisp
;; Check agent loaded status
(gptel-agent--task t)  ; Returns agent info alist

;; Verify function is defined
(message "Task fbound: %s" (fboundp 'gptel-agent--task))

;; Check agent count
(message "Agents count: %s" (length gptel-agent--agents))

;; Run specific tests
./scripts/run-tests.sh grader
```

**Expected Results**:
```
:gptel-agent-loaded t
:gptel-agent--task-fbound t
:gptel-agent--agents-count 13
```

## Decision Matrix: Subagent vs Skill vs Protocol

| Criteria | Subagent | Skill | Protocol |
|----------|----------|-------|----------|
| **Context Isolation** | ✅ Full | ❌ Shared | ❌ Shared |
| **Parallel Execution** | ✅ Yes | ❌ No | ❌ No |
| **Dedicated Model** | ✅ Yes | ❌ No | ❌ No |
| **External Tools/API** | ✅ Yes | ✅ Yes | ❌ No |
| **Requires Scripts** | Optional | ✅ Yes | ❌ No |
| **Parent Context Access** | Limited | Full | Full |

### When to Use Subagent

1. **Context isolation needed** - Review shouldn't pollute parent agent's context
2. **Parallel execution** - Parent can spawn reviewer and continue other work
3. **Tool profile restriction** - Reviewer only needs readonly tools
4. **Dedicated model** - Use cheaper model (gpt-4o-mini) for review
5. **Long-running task** - Subagent persists independently

### When to Use Skill

1. **Shared context required** - Task benefits from parent's full context
2. **Tool orchestration** - Needs multiple tools in sequence
3. **Quick procedure** - Simple task that doesn't warrant isolation

### When to Use Protocol

1. **Pure procedure** - No external dependencies
2. **Documentation** - Stored in `mementum/knowledge/{name}-protocol.md`
3. **No state** - Stateless operation

## Directory Structure

```
mementum/
├── knowledge/
│   └── {name}-protocol.md      # Pure procedures
assistant/
├── skills/
│   └── {name}/
│       ├── skill.yaml          # Skill definition
│       └── scripts/            # Tool scripts, REPL, APIs
eca/
└── prompts/
    └── {name}_agent.md         # Subagent definition
```

## Testing Subagents

### Test File Structure

```elisp
;; tests/test-grader-subagent.el
(require 'ert)
(require 'gptel-tools-agent)

(ert-deftest test-grader-subagent-llm-used ()
  "Verify grader uses LLM instead of local fallback."
  (should (gptel-agent--task-p t)))

(ert-deftest test-grader-subagent-json-parse ()
  "Verify JSON parser handles grader output format."
  (should (string-match-p "score"
                          (gptel-benchmark-parse-grader-output
                           "{\"score\": 85}"))))

;; Run tests
(ert-run-tests t)
```

### TDD Approach for Subagent Bugs

1. **Write test first** - Tests reveal actual behavior
2. **Run tests** - Should fail (red)
3. **Trace** - Identify root cause
4. **Fix** - Apply fix
5. **Verify** - Tests pass (green)

## Related Topics

- [gptel-agent](gptel-agent) - Main agent framework
- [gptel-tools](gptel-tools) - Tool definitions
- [Advice Debugging](advice-debugging) - Debugging advice conflicts
- [Context Management](context-management) - Context isolation patterns
- [Skill](skill) - Alternative to subagent for shared-context tasks
- [Protocol](protocol) - For stateless procedures
- [Grader](grader) - Example subagent for code evaluation

## Patterns and Anti-Patterns

### Patterns ✅

| Pattern | Description |
|---------|-------------|
| Single Responsibility | One subagent per task |
| Minimal Context | Pass only necessary info |
| Tool Restriction | Limit tools to required set |
| Model Selection | Use appropriate model per task |
| Single Advice | One advice per function |

### Anti-Patterns ❌

| Anti-Pattern | Problem |
|--------------|---------|
| Multiple advices on same function | Unpredictable behavior |
| Shared context when isolation needed | Token bloat, pollution |
| Wrong model selection | Cost/performance mismatch |
| Missing require | Silent fallback to local |
| Global variable shadowing | Breaks function definitions |

---

*Tags: gptel, subagent, agent, debug, emacs, lisp, architecture, context-isolation*
*Category: knowledge*
*Status: active*