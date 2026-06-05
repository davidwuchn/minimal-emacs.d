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

| Priority | Improvement | Status | Implementation |
|----------|------------|--------|----------------|
| P0 | Schema extraction at memory commit | **Done** | Heuristic triple extraction in `gptel-auto-workflow-memory-schema.el`; JSON index |
| P0 | Frequency-based schema stability | **Done** | τ=3 threshold in `stable-p`; ontology-router fallback |
| P1 | Conflict detection | **Done** | Entity overlap scan in `detect-conflicts` |
| P1 | Bidirectional memory-code links | **Done** | `@memory:` scan + `files-for-memory`/`memories-for-file` |
| P1 | Temporal versioning for memories | **Done** | `valid-from`/`valid-until` frontmatter; auto-supersede on write |
| P2 | Graph retrieval for recall | **Done** | PPR-lite neighbor walk in `entity-neighbors`/`retrieve` |
| P2 | Entity-level synonymy edges | **Done** | `gptel-auto-workflow--memory-schema-synonymy-edges` via git-embed file similarity + entity cross-reference |
| P3 | Multi-agent shared memory per experiment | **Done** | `experiment-context` builds scoped memory for subagent prompts |
| P3 | Hub suppression for memory ranking | **Done** | IDF weighting `1/log(deg+1)` in `entity-idf`/`rank-entities` |
