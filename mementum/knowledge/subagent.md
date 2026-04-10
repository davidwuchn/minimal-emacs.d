---
title: subagent
status: open
---

Synthesized from 3 memories.

💡 grader-subagent-debug-session

## Problem
Grader subagent always fell back to local grading, never used LLM.

## Root Cause Chain
1. `gptel-tools-agent.el` did NOT require `gptel-agent`
2. `gptel-agent--task` was never defined (fboundp returned nil)
3. `gptel-agent--agents` was declared nil (shadowing)
4. `(fboundp 'gptel-agent--task)` → nil → local grading fallback

## TDD Approach
1. Wrote tests first: `tests/test-grader-subagent.el`
2. Tests revealed actual behavior
3. Tests guided fix
4. Tests verify fix works

## Fixes Applied
1. `(require 'gptel-agent)` at top of `gptel-tools-agent.el`
2. Removed redundant `(defvar gptel-agent--agents nil)`
3. Fixed JSON parser to handle grader output format

## Verification
```
:gptel-agent-loaded t
:gptel-agent--task-fbound t  
:gptel-agent--agents-count 13
:grader-model "qwen3.5-plus"
:executor-model "qwen3.5-plus"
```

## Key Files
- `lisp/modules/gptel-tools-agent.el` - Added require
- `lisp/modules/gptel-benchmark-subagent.el` - Fixed JSON parser
- `tests/test-grader-subagent.el` - 8 tests, all pass

## λ debug
```
λ bug. test → red → trace → fix → green
λ verify. ./scripts/run-tests.sh grader
```

---
title: Reviewer as Subagent vs Skill
φ: 0.85
e: reviewer-is-subagent
λ: when.choosing.skill.or.subagent
Δ: 0.05
evidence: 1
---

💡 Code reviewer is better as subagent than skill. Key decision factors:

## Decision Matrix

| Task | Use | Why |
|------|-----|-----|
| Pure procedure (no deps) | Protocol → `mementum/knowledge/` | No external dependencies |
| Has external tools/API | Skill → `assistant/skills/` | Needs scripts, REPL, API |
| Context isolation needed | Subagent → `eca/prompts/` | Won't pollute parent |
| Parallel execution | Subagent | Can run concurrently |
| Dedicated model | Subagent | Cheaper/faster model option |
| Shared context | Skill | Uses parent's context |

## Reviewer → Subagent

Reasons:
1. **Context isolation** - Review shouldn't pollute parent agent's context
2. **Parallel** - Parent can spawn reviewer and continue other work
3. **Tool profile** - Reviewer only needs readonly tools
4. **Dedicated model** - Can use cheaper model (gpt-5.4-mini) for review
5. **Already defined** - eca/config.json has reviewer subagent

## Structure

```
Protocols:    mementum/knowledge/{name}-protocol.md
Tool Skills:  assistant/skills/{name}/ (with REPL/API deps)
Subagents:    eca/prompts/{name}_agent.md (context isolation)
```

# Subagent Overlay Conflict

**Date**: 2026-03-29

**Problem**: Subagent overlays appearing in *Messages* buffer despite routing fixes.

**Root Cause**: TWO conflicting advices on `gptel-agent--task`:
1. `my/gptel-agent--task-override` with `:override` (old, line 461)
2. `gptel-auto-workflow--advice-task-override` with `:around` (new, in projects.el)

The old `:override` advice completely replaces the original function and creates overlays in `parent-buf`, which can be *Messages* if the FSM was created there.

**Symptoms**:
- Overlays still appear in *Messages* after "fixes"
- Executor and Grader overlays visible in wrong buffer
- "Buffer gptel.el modified; kill anyway?" prompts in headless mode

**Solution**:
1. Remove old `:override` advice
2. Merge caching logic into new `:around` advice
3. Add `kill-buffer` query suppression for headless mode

**Files**:
- `lisp/modules/gptel-tools-agent.el:461` - old advice registration
- `lisp/modules/gptel-auto-workflow-projects.el:212` - new advice

**Pattern**: Multiple advices on same function with different types (`:override` vs `:around`) causes unpredictable behavior. Use ONE advice type.