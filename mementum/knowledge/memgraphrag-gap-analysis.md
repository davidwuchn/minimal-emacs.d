---
title: MemGraphRAG vs OV5 Gap Analysis
date: 2026-06-05
status: active
category: research
tags: [graphrag, multi-agent, memory, knowledge-graph, gap-analysis]
related: [nucleus-patterns.md, patterns.md]
---

# MemGraphRAG vs OV5 Gap Analysis

Source: [MemGraphRAG](https://github.com/XMUDeepLIT/MemGraphRAG) (KDD 2026)
Paper: arXiv:2606.00610

## Core Innovation

MemGraphRAG solves the **recall-relevance tradeoff** in GraphRAG. Isolated local extraction produces three systematic defects: thematic irrelevance, logical inconsistency, structural fragmentation. Fix: three-layer global memory (Schema→Fact→Passage) shared by three agents (Extraction, Detection, Resolution), retrieved via Personalized PageRank. Result: 59.25% avg accuracy (+2.10% over LinearRAG).

## OV5 Gaps That MemGraphRAG Addresses

1. **No schema abstraction layer** — OV5 memories are flat text. MemGraphRAG's `Freq(s) >= τ` schema promotion creates empirically grounded abstraction.
2. **No automated conflict detection between memories** — Contradictory mementum memories coexist silently. MemGraphRAG detects mutual/temporal/granularity conflicts.
3. **No bidirectional navigation** — OV5 links knowledge→memory one-way. MemGraphRAG has Schema↔Fact↔Passage indices.
4. **No entity extraction from free-form text** — Memories are markdown, not triples. No graph-based reasoning over knowledge.
5. **No temporal versioning** — Old memories remain valid forever. No obsolescence detection.
6. **No multi-agent shared memory** — OV5 subagents operate in isolation. No real-time consistency enforcement.
7. **File-level similarity only** — OV5 semantic clustering is file-to-file. MemGraphRAG operates at entity/concept granularity.

## OV5 Advantages Over MemGraphRAG

1. **Competitive strategy selection** (champion league) — MemGraphRAG uses fixed agent roles.
2. **Self-healing** — MemGraphRAG has no mechanism to repair broken evaluators.
3. **Formal logical consistency** — Horn SAT + OWL/SHACL vs LLM-based resolution (probabilistic).
4. **Strategy inheritance** (π Synthesis) — No propagation mechanism in MemGraphRAG.
5. **Holdout evaluation** — MemGraphRAG has no overfitting detection.
6. **Provider portability** — P(λ)=90.7% across 5 backends; MemGraphRAG is GPT-dependent.
7. **Cybernetic self-regulation** (VSM + Wu Xing) — MemGraphRAG is a pipeline, not a self-regulating system.
8. **Operational taxonomy** (KIBC 15-axis) — No mutation classification in MemGraphRAG.
9. **Persistence across runs** — OV5 survives restarts; MemGraphRAG rebuilds per corpus.
10. **Behavioral specification** (Allium v3) — Formal checking vs LLM prompting.

## Actionable Improvements

| Priority | Improvement | Path |
|----------|------------|------|
| P0 | Schema extraction at memory commit | LLM triple extraction in pre-commit; store in `mementum/.ov5-memory-index.json` |
| P0 | Frequency-based schema stability | τ threshold for ontology-router: ≥3 observations before routing uses new patterns |
| P1 | Conflict detection daemon | Weekly vector similarity scan + LLM classification; report to `mementum/knowledge/conflicts.md` |
| P1 | Bidirectional memory-code links | `@memory:` annotations in commits; reverse index code→memories |
| P1 | Temporal versioning for memories | `valid-from`/`valid-until` frontmatter; supersede mechanism |
| P2 | Personalized PageRank for recall | Build entity graph from triples; PPR retrieval as alternative to git-grep |
| P2 | Entity-level synonymy edges | Embed entities; similarity >0.85 → synonymy edge |
| P3 | Multi-agent shared memory per experiment | `ov5-experiment-memory` struct; inject into subagent prompts |
| P3 | Hub suppression for memory ranking | Penalize generic memories (1/log(deg+1)); boost rare (IDF) |
