---
title: Ontology × Behaviors × Skill Graph × Context — Four-Way Relationship
φ: 0.85
e: ontology-behaviors-skill-context-relationship
λ: when.designing.agent.architecture
Δ: 0.15
evidence: 3
sources:
  - gptel-auto-workflow-ontology-strategy.el
  - gptel-auto-experiment-ai-behaviors.el
  - ov5-skill-graph-self-evolution.md
  - gptel-tools-agent-prompt-build.el (context mgmt)
---

💡 Four systems are not independent. They form a decision hierarchy that must co-evolve.

## The Hierarchy

```
1. ONTOLOGY     → "What category?" → :programming
2. ONTOLOGY     → "Which strategy/backend?" → DeepSeek
3. BEHAVIORS    → "What persona?" → #deterministic
4. SKILL GRAPH  → "Which skills?" → [planning → clojure-expert]
5. CONTEXT      → "Can we fit?" → Task + Behaviors + Skills + Reserve = 7.5k ✓
6. EXECUTE      → Agent runs with composed prompt
7. EVOLVE       → AutoTTS trace updates all four systems
```

## Cross-System Links

| From | To | Mechanism |
|------|----|-----------|
| **Ontology** | Behaviors | Category selects default hashtags (:programming → #deterministic) |
| **Ontology** | Skill Graph | Router top-k feeds graph seeds; graph adds `:graph-neighbor-success` + `:graph-edge-strength` to ontology scores |
| **Behaviors + Skills** | Context | Both consume same token pool; skills truncate first if overflow |
| **Context** | Skill Graph | Molecule size ≤10 atoms = context physics (10 × 300 tokens = 3k budget) |
| **Execution Trace** | All four | AutoTTS feeds: ontology scores, behavior keep-rates, edge reinforcement, token efficiency |

## Key Constraint

All four must co-evolve from the **same execution traces**. Optimizing one dimension while ignoring others breaks the stack — e.g., maximizing skill composition without respecting context budget overflows and degrades performance.

## Decision

AutoTTS trace format must include: category, hashtags, skill-names, backend, token-usage, outcome. Single trace updates all four systems atomically.
