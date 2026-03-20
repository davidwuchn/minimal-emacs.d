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