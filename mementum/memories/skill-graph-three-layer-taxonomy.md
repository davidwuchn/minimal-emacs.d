---
title: Skill Graphs — Design-Time Compilation Beats Runtime Traversal
φ: 0.90
e: skill-graph-three-layer-taxonomy
λ: when.skill.composition.needed
Δ: 0.15
evidence: 3
sources:
  - Graph-of-Skills (GitHub: davidliuk)
  - SkillGraph (arXiv:2605.12039v1)
  - Shiv Sakhuja Skill Graphs 2.0 (X thread)
---

💡 Runtime graph traversal causes exponential reliability decay. The solution is **design-time compilation** into three explicit layers.

## The Three Sources

| Source | Approach | Runtime? |
|--------|----------|----------|
| Graph-of-Skills | PPR over typed edges (dependency/workflow/semantic) | Yes — graph traversal |
| SkillGraph | BFS + beam search + topological sort | Yes — graph traversal |
| Shiv Sakhuja | Atoms → Molecules → Compounds | **No** — hardcoded workflows |

## The Taxonomy

```
Atoms: Single-purpose primitives, NEVER call skills (~99% reliability)
  └─ Molecules: Hardcoded atom sequences, explicit workflow (~90%)
       └─ Compounds: Human-driven orchestrators, select molecules (~70%)
```

## Key Constraints

- **Atoms never recurse** — eliminates depth fragility
- **Molecules ≤10 atoms** — Shiv's empirical ceiling
- **Compounds ≤10 molecules** — human judgement required
- **Graph is compile-time only** — PPR/BFS useful for discovering atom compositions, not runtime dispatch

## OV5 Integration

| System | Role |
|--------|------|
| `skill-routing-onto.el` | Seed selection (which atoms match task) |
| `gptel-tools-agent-prompt-build.el` | Parse `level:` + `atoms:` frontmatter |
| AutoTTS traces | Per-level success rate tracking |
| gptel context mgmt | Enforce `max-skill-chars` budget |

## Why Pure Elisp

Python script = subprocess + file I/O + impedance mismatch. Elisp native = direct function calls to ontology router, AutoTTS, gptel state. No runtime graph traversal. Graph algorithms (PPR, BFS) run at design time to suggest molecule compositions, which humans validate and hardcode.

## Decision

Implement `ov5-skill-graph.el` as pure elisp with:
1. `level:` frontmatter (atom/molecule/compound)
2. `atoms:` / `molecules:` explicit composition lists
3. `ov5-sg--validate-level` enforcing no-skill-calls for atoms
4. Molecule executor with hardcoded sequences (no runtime graph)
5. AutoTTS per-level reliability tracking

## See Also

- `ov5-skill-graph-self-evolution.md` — Self-evolution architecture integrating AutoTTS, AutoGo, ontology router
