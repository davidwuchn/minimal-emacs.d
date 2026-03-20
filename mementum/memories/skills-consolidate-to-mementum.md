---
title: Skills Consolidate into Mementum Protocols
φ: 0.85
e: consolidate-skills-to-mementum
λ: when.skill.exists
Δ: 0.05
evidence: 1
---

💡 Skills don't need thin wrappers. Protocol content belongs in `mementum/knowledge/{domain}-protocol.md`.

## What We Learned

Skills (continuous-learning, planning) were 90% protocol/procedure content that maps directly to Mementum operations:

| Skill Component | Mementum Equivalent |
|-----------------|---------------------|
| `λ(observe)` | `store` |
| `λ(learn)` | `recall` |
| `λ(evolve)` | `metabolize` |
| `instincts/personal/` | `mementum/memories/` |
| `instincts/library/` | `mementum/knowledge/` |
| Session state | `mementum/state.md` |
| Project facts | `mementum/knowledge/project-facts.md` |

## Key Insight

Skill wrappers add indirection without value. The protocol itself IS the knowledge. Store it in `mementum/knowledge/` and AI reads it via `orient()`.

## Architecture Simplified

```
Before: AGENTS.md → skills/ → SKILL.md → procedures → memories
After:  AGENTS.md → mementum/ → knowledge/protocol.md → direct execution
```

## When to Apply

- Any skill with procedural content → migrate to `mementum/knowledge/{domain}-protocol.md`
- Skills with state → use `mementum/state.md`
- Skills with instincts/patterns → use `mementum/memories/`