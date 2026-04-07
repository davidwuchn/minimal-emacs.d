---
title: Subagent Patterns for gptel-auto-workflow
status: active
category: knowledge
tags: [subagent, agent, delegation, context-isolation, parallel]
related: [mementum/memories/reviewer-as-subagent.md, mementum/memories/grader-subagent-debug-session.md, mementum/memories/subagent-overlay-conflict.md]
---

# Subagent Patterns for gptel-auto-workflow

Patterns for delegating work to subagents in auto-workflow experiments.

## Decision Matrix: Skill vs Subagent vs Protocol

| Task Type | Use | Why |
|-----------|-----|-----|
| Pure procedure (no deps) | Protocol → `mementum/knowledge/` | No external dependencies |
| Has external tools/API | Skill → `assistant/skills/` | Needs scripts, REPL, API |
| Context isolation needed | Subagent → `eca/prompts/` | Won't pollute parent |
| Parallel execution | Subagent | Can run concurrently |
| Dedicated model | Subagent | Cheaper/faster model option |
| Shared context | Skill | Uses parent's context |

## Reviewer → Subagent

**Why reviewer should be a subagent:**

1. **Context isolation** - Review shouldn't pollute parent agent's context
2. **Parallel** - Parent can spawn reviewer and continue other work
3. **Tool profile** - Reviewer only needs readonly tools
4. **Dedicated model** - Can use cheaper model for review
5. **Already defined** - `eca/config.json` has reviewer subagent

## Grader Subagent Debug Pattern

**Problem:** Grader subagent always fell back to local grading, never used LLM.

**Root Cause Chain:**
1. `gptel-tools-agent.el` did NOT require `gptel-agent`
2. `gptel-agent--task` was never defined (fboundp returned nil)
3. `gptel-agent--agents` was declared nil (shadowing)
4. `(fboundp 'gptel-agent--task)` → nil → local grading fallback

**TDD Approach:**
1. Wrote tests first: `tests/test-grader-subagent.el`
2. Tests revealed actual behavior
3. Tests guided fix
4. Tests verify fix works

**Fixes:**
```elisp
(require 'gptel-agent)  ;; At top of gptel-tools-agent.el
;; Remove redundant: (defvar gptel-agent--agents nil)
```

**Verification:**
```
:gptel-agent-loaded t
:gptel-agent--task-fbound t  
:gptel-agent--agents-count 13
```

## Overlay Conflict Pattern

**Problem:** Subagent overlays appearing in wrong buffers (e.g., *Messages*).

**Root Cause:** TWO conflicting advices on same function:
1. Old `:override` advice completely replaces original
2. New `:around` advice wraps original

**Solution:**
1. Remove old `:override` advice
2. Merge caching logic into new `:around` advice
3. Use ONE advice type per function

**Pattern:** Multiple advices on same function with different types causes unpredictable behavior.

## Key Principles

1. **Require dependencies** - `gptel-agent` must be loaded before checking `fboundp`
2. **Single advice type** - Use either `:override` OR `:around`, not both
3. **Context isolation** - Subagents don't pollute parent's context
4. **Tool profiles** - Subagents can have restricted tool sets
5. **Model selection** - Subagents can use cheaper/faster models
6. **TDD for debugging** - Write tests to reveal actual behavior

## Related Memories

- `reviewer-as-subagent.md` - Decision matrix for reviewer
- `grader-subagent-debug-session.md` - Debug pattern with TDD
- `subagent-overlay-conflict.md` - Multiple advice conflict