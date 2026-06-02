---
title: OV5 Skill Graph Self-Evolution Architecture
φ: 0.85
e: ov5-skill-graph-self-evolution
λ: when.skill.graph.needed
Δ: 0.20
evidence: 4
sources:
  - Graph-of-Skills (GitHub: davidliuk)
  - SkillGraph (arXiv:2605.12039v1)
  - Shiv Sakhuja Skill Graphs 2.0 (X thread)
  - OV5 existing: AutoTTS, AutoGo, ontology router, evolution cycle
---

💡 OV5 already has all infrastructure for self-evolving skill graphs. No new systems needed — just wire into existing closed loop.

## The Loop

1. **Pipeline executes** with current skills → AutoTTS traces every call + outcome
2. **Evolution cycle** (hourly cron) analyzes traces
3. **Update node stats**: usage-count, success-rate per skill
4. **Update edge weights**: reinforce +0.05 on successful paths, decay *0.99, prune <0.05
5. **Evaluate triggers**: insert (new skills from failures), merge (Jaccard ≥0.85), split (success ∈ [0.15,0.4]), deprecate (usage≥20, p<0.15)
6. **AutoGo A/B tests** proposed molecules vs baselines
7. **Champion league** crowns winners after ≥10 experiments
8. **Commit** evolved graph to `mementum/knowledge/skill-graph.json`

## Key Integration Points

| System | Role |
|--------|------|
| AutoTTS | Node stats + edge co-occurrence discovery |
| AutoGo | A/B test proposed molecules |
| Ontology router | Add `:graph-neighbor-success` + `:graph-edge-strength` dimensions |
| Evolution cycle | Hourly trigger for `ov5-sg-evolve` |
| Mementum | Git-persist `skill-graph.json` |

## Design-Time vs Runtime

Graph algorithms (PPR, BFS) run at **design time** to suggest molecule compositions. Runtime uses **hardcoded molecules** — no traversal, no depth fragility.

## Implementation

Pure elisp: `ov5-skill-graph.el` (data structures) + `ov5-skill-graph-evolve.el` (evolution). Hook into `gptel-auto-workflow--evolution-hook`.
