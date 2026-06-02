---
title: AI Behaviors vs Skill Graph — Orthogonal Systems
e: ai-behaviors-vs-skill-graph
φ: 0.85
λ: when.designing.agent.architecture
Δ: 0.10
evidence: 2
sources:
  - gptel-auto-experiment-ai-behaviors.el
  - ov5-skill-graph-self-evolution.md
---

💡 AI Behaviors and Skill Graph are **orthogonal** — they solve different problems and stack.

## The Split

| Dimension | AI Behaviors | Skill Graph |
|-----------|--------------|-------------|
| **What** | Persona/style hashtags (#deterministic) | Capabilities (clojure-expert) |
| **Content** | Prompt snippets (how to act) | Instructions + tools (what to do) |
| **Composition** | Recursive expansion (compose files) | Hardcoded sequences (molecules) |
| **Evolution data** | (category × hashtag) success rates | (skill × skill) co-occurrence + success |
| **Injection** | Agent prompt prefix | Agent context as skill bundle |

## How They Stack

```
Compound: "Build this feature"
  ├─ Behavior: #creative (exploration phase)
  ├─ Molecule: [research → design → implement]
  │     ├─ Atom: research (behavior: #thorough)
  │     ├─ Atom: design (behavior: #structured)
  │     └─ Atom: implement (behavior: #deterministic)
  └─ Behavior: #concise (final output)
```

## Integration Points

- **Skill graph evolution** considers behavior: did `clojure-workflow` + `#deterministic` outperform `#creative`?
- **Behavior evolution** considers skill level: atoms → `#deterministic`, compounds → `#creative`
- AutoGo can A/B test: same molecule, different behaviors

## Decision

Both systems evolve. Neither replaces the other. Design-time integration: molecule definitions include default behavior hashtags.
