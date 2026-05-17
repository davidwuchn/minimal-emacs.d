---
title: Graphify Deep Dive — Cluster + Analyze Patterns
date: 2026-05-17
symbol: 💡
---

# Graphify Deep Dive — Cluster + Analyze Patterns

## New Patterns Discovered

### cluster.py

| Pattern | What | Applied |
|---------|------|---------|
| Graceful degradation | Try Leiden, fallback Louvain | — |
| Isolate handling | Separate degree-0 nodes | — |
| Community splitting | Split oversized (>25%) communities | — |
| Cohesion scoring | Ratio of internal edges to possible max | ✅ |

### analyze.py

| Pattern | What | Applied |
|---------|------|---------|
| Surprise scoring | Composite: confidence + file-crossing + repo-crossing + community-bridging + peripheral-to-hub | — |
| God nodes filtering | Exclude file hubs, method stubs, concept nodes | — |
| Suggested questions | 5 types: ambiguous, bridge, verify, isolated, cohesion | — |
| Graph diff | Compare two snapshots, report changes | — |
| File category detection | code/paper/image/doc from extension | — |
| Cross-file detection | Top-level directory comparison | — |

## What We Applied

### Module Cohesion Scoring (cluster.py cohesion_score)
`module-cohesion(file-path)`: ratio of internal requires/declares to total.
Low cohesion (< 0.5) = grab-bag module, candidate for refactoring.
`find-surprising-modules(module-dir)`: finds modules with cohesion below 0.5.

### How It Fits the Pipeline
The analyzer can use `find-surprising-modules` to prioritize targets:
- Low cohesion modules → likely need refactoring
- High cohesion modules → well-structured, lower priority
- This replaces random/error-based target selection with structural analysis

## Remaining Deep Patterns (not yet applied)

1. **Edge surprise scoring**: Our mementum edges could be scored like graphify's
   `_surprise_score()` — cross-module references that bridge communities
   would be flagged as "surprising connections" worth investigating.

2. **God node detection**: Our 89 modules have architectural god nodes —
   `gptel-request`, `plist-get`, `gptel-tools-agent--load-module` etc.
   Identifying these would help the LLM understand what's architecturally
   central vs peripheral.

3. **Suggested questions from graph structure**: Low-cohesion communities
   generate questions like "Should X be split into smaller modules?" —
   this could feed directly into experiment hypotheses.

4. **Graph diff for evolution tracking**: Track which modules gained/lost
   defuns between evolution cycles. Surface structural changes.
