---
title: Subagent Architecture and Best Practices
status: active
category: knowledge
tags: [subagent, gptel, agent-design, architecture, debugging]
---

# Subagent Architecture and Best Practices

## Overview

A **subagent** is a specialized autonomous agent spawned by a parent agent to handle specific tasks with context isolation, dedicated tooling, and independent model selection. Unlike skills, subagents run in their own execution context and can be parallelized.

**Key Characteristics:**

| Characteristic | Subagent | Skill |
|---------------|----------|-------|
| Execution Context | Isolated | Shared with parent |
| Parallel Execution | ✅ Yes | ❌ No |
| Tool Profile | Dedicated | Inherited |
| Model Selection | Independent | Parent's model |
| Context Pollution | None | Possible |

## When to Use Subagents

### Decision Matrix

Use this matrix to decide between subagent, skill, or protocol for your task:

| Task Type | Use | Reasoning |
|-----------|-----|-----------|
| Pure procedure, no deps | Protocol (`mementum/knowledge/`) | No external dependencies needed |
| Has external tools/API | Skill (`assistant/skills/`) | Needs scripts, REPL, API access |
| Context isolation required | Subagent (`eca/prompts/`) | Won't pollute parent context |
| Parallel execution needed | Subagent | Can run concurrently with parent |
| Dedicated/cheaper model | Subagent | Use gpt-5.4-mini for reviews |
| Shared context preferred | Skill | Inherits parent's conversation |

### Signal Examples

**Use Subagent When You See:**
- "Review these changes without affecting the main task"
- "Run multiple analyses in parallel"
- "Use a specialized toolset that differs from parent"
- "Isolate memory/context between tasks"
- "Reduce costs by using a smaller model"

**Use Skill When You See:**
- "Extend the current conversation's capabilities"
- "Need access to parent's full context"
- "Quick, stateless operation"
- "Tool wrapper around existing functionality"

## Subagent Implementation Patterns

### Pattern 1: Basic Subagent Definition

Subagents are defined in `eca/prompts/` with a standardized structure:

```markdown
# {name}_agent.md

You are a specialized {task} agent.

## Your Role
[Detailed role description]

## Tools Available
- Read (readonly access)
- Grep (search)
- Glob (file discovery)
- [Subagent-specific tools]

## Constraints
- Do not modify files directly
- Report findings to parent agent
- Use context isolation
```

### Pattern 2: Subagent Configuration

Define subagent tool profiles in `eca/config.json`:

```json
{
  "agents": {
    "reviewer": {
      "model": "qwen3.5-plus",
      "tools": ["Read", "Grep", "Glob", "Code_Usages"],
      "context-window": 128000
    },
    "grader": {
      "model": "qwen3.5-plus",
      "tools": ["Read", "Grep"],
      "timeout": 60
    }
  }
}
```

### Pattern 3: TDD for Subagent Development

Follow test-driven development when building subagent functionality:

```bash
# 1. Write tests first
./scripts/run-tests.sh grader-subagent

# 2. Run tests to reveal actual behavior
# Tests should fail initially

# 3. Implement the fix
# Tests guide the implementation

# 4. Verify all tests pass
# Final verification
```

**Example Test Structure** (`tests/test-grader-subagent.el`):

```elisp
(ert-deftest test-grader-subagent-uses-llm ()
  "Grader should use LLM when gptel-agent is loaded."
  (should (fboundp 'gptel-agent--task)))

(ert-deftest test-grader-subagent-json-parsing ()
  "Grader should handle its output format correctly."
  (let ((output (grader-parse "{\"score\": 85, \"feedback\": \"good\"}")))
    (should (= 85 (alist-get 'score output)))))
```

## Debugging Subagent Issues

### Common Failure Mode: Local Fallback

**Problem**: Subagent always falls back to local processing instead of using LLM.

**Root Cause Chain** (grader-subagent-debug-session):

```
1. Module requires chain broken
   ↓
2. gptel-agent--task never defined
   ↓
3. (fbo
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-GxsKac.txt. Use Read tool if you need more]...