---
title: "Helium vs OV5: Workflow Optimization Gaps"
status: active
category: architecture
tags: [helium, caching, scheduling, workflow-optimization, kv-cache]
related: [deep-searcher-vs-ov5-gaps, clojure-first-multiplatform-architecture]
depends-on: []
---

# Helium vs OV5: Workflow Optimization Gaps

**Date**: 2026-06-16  
**Source**: https://github.com/mlsys-io/helium_demo  
**Paper**: helium-extended.pdf (MLSys workflow-aware LLM serving)

## Helium's Core Innovation

Helium models agentic workflows as **query plans** — DAGs of typed operators with three-level caching and cache-aware scheduling. The central insight: agent workflow performance is dominated by LLM call latency, so caching (prompts, KV, intermediate results) and speculative parallelism are the most effective optimizations.

## Architecture Comparison

| Dimension | Helium | OV5 |
|-----------|--------|-----|
| **Workflow model** | DAG of typed operators | Linear FSM (phases) |
| **Caching** | Three-level: prompt, KV, intermediate | None (stateless per-call) |
| **Scheduling** | Cache-aware (CAS) with radix tree | Sequential dispatch |
| **Parallelism** | Speculative branch exploration | Sequential hypothesis testing |
| **Deduplication** | Operator signature-based merging | None |
| **KV precomputation** | Proactive prefix KV cache | None |
| **Self-healing** | None | Source-level evolution |
| **Monitoring** | None | Meta-improvement agent |
| **Ontology** | None | Knowledge graphs + Allium |
| **Quality gates** | Simple pass/fail | 7 gates + complexity gate |
| **Isolation** | None | Git worktrees |
| **Memory** | In-memory caches | Datahike World Store + mementum |
| **Human governance** | None | Approval queue + risk tiers |

## Helium's Three-Level Cache Strategy

### 1. Prompt Cache (Result-Level)
- `PromptCacheManager` stores per-`WorkerInput` LRU caches
- Keys: hashable generation configs + prompt content
- Only enabled for temperature == 0 (deterministic outputs)
- Skips repeated LLM calls entirely

### 2. KV Cache (Prefix-Level)
- `KVCacheManager` wraps LMCache
- `precompute_kv_cache()` runs prompts with `max_tokens=1` to populate prefix KV states
- Supports proactive pinning via `KVCacheClient.pin()`
- Reuses partial computation across similar prompts

### 3. Intermediate Result Reuse
- `CacheResolver` walks graph, computes cache keys, returns `cached_outputs`
- `CacheFetchOp` fetches previously stored results for specific row indices
- Combined with `SliceOp` and `ConcatOp` to reuse partial outputs

## Cache-Aware Scheduling (CAS)

- Builds `SchedulingTree` from `TemplatedRadixTree` of prompt prefixes
- Uses LLM dependency depths, profiling-estimated token usage, worker capacity
- `SchedulingNode.schedule()` emits ops when non-blocking relative to virtual token step
- `adjust_token_step()` advances based on released sequences and batch limits
- Goal: maximize KV cache reuse by scheduling similar-prefix ops back-to-back

## Operator Deduplication

- Each `Op` declares `signature()` for functional equivalence
- `HeliumOptimizer._merge_nodes()` deduplicates ops with identical signatures
- Merges multiple agent graphs into single execution plan
- Weakly connected components processed together for cross-branch batching

## Highest-Leverage Gaps for OV5

### Gap 1: Prompt Prefix Caching
**Problem**: OV5 makes identical subagent prompts across experiments in same run without caching.  
**Helium solution**: LRU cache keyed by (backend, model, prompt hash) for temperature==0 calls.  
**OV5 implementation**: Add `gptel-ext-prefix-cache.el` with per-run LRU cache. Key: `(backend . model . prompt-hash)`. Value: `(result . timestamp)`. Invalidate on backend/model change.

### Gap 2: Intermediate Result Materialization
**Problem**: OV5 re-computes research findings for each experiment even when same target.  
**Helium solution**: `CacheFetchOp` + `SliceOp` reuse intermediate outputs.  
**OV5 implementation**: Persist research findings per-run in `var/tmp/run-<id>/research-<target>.edn`. Before dispatching researcher subagent, check if result exists. Reuse if found.

### Gap 3: Cache-Aware Scheduling
**Problem**: OV5 dispatches subagents sequentially without considering prefix sharing.  
**Helium solution**: CAS scheduler orders ops to maximize KV cache reuse.  
**OV5 implementation**: Group subagent calls by (backend, model, prompt-prefix). Dispatch groups back-to-back. Track prefix overlap in routing decisions.

### Gap 4: Speculative Parallel Branches
**Problem**: OV5 tests hypotheses sequentially in hypothesis-generation phase.  
**Helium solution**: Launch candidate branches concurrently, merge results.  
**OV5 implementation**: In `gptel-auto-workflow--generate-hypotheses`, launch top-N diverse hypotheses in parallel (not just highest-diversity). Merge results after all complete.

### Gap 5: Operator Deduplication
**Problem**: Multiple experiments may make identical LLM calls (same target, same strategy).  
**Helium solution**: Signature-based deduplication merges equivalent ops.  
**OV5 implementation**: Before dispatching subagent, compute signature `(task-type . target . strategy-hash)`. Check if signature already computed in current run. Reuse if found.

## Implementation Priority

1. **Prompt prefix caching** (Gap 1) — Lowest effort, highest impact. Reuse identical prompts across experiments.
2. **Intermediate result materialization** (Gap 2) — Medium effort, high impact. Avoid re-computing research.
3. **Cache-aware scheduling** (Gap 3) — Medium effort, medium impact. Order dispatches for prefix sharing.
4. **Speculative parallel branches** (Gap 4) — High effort, medium impact. Requires async orchestration.
5. **Operator deduplication** (Gap 5) — High effort, low impact (OV5 already has some via target routing).

## What OV5 Has That Helium Lacks

- **Self-healing**: Helium can't fix its own code when evaluators break
- **Monitoring agent**: Helium has no meta-improvement layer
- **Ontology learning**: Helium doesn't build knowledge graphs from experiments
- **7 gates**: Helium has simple pass/fail; OV5 has complexity gate, AI review, pi synthesis, champion league
- **Git worktree isolation**: Helium doesn't isolate experiments
- **Datahike World Store**: Helium has in-memory caches; OV5 has immutable, queryable, git-like memory
- **Approval queue**: Helium has no human governance for high-risk proposals
- **VSM diagnostics**: Helium doesn't have five-element health model

## Strategic Insight

Helium optimizes **within a single workflow run** (caching, scheduling, deduplication). OV5 optimizes **across workflow runs** (ontology learning, self-healing, monitoring). They solve different problems at different timescales.

**Integration opportunity**: Add helium's within-run optimizations to OV5's existing across-run learning. This gives OV5 both short-term (prefix caching) and long-term (ontology) memory.

## Next Actions

1. Implement `gptel-ext-prefix-cache.el` — per-run LRU cache for identical prompts
2. Add intermediate result materialization — persist research findings per-run
3. Add cache-aware scheduling — group subagent dispatches by prefix similarity
4. Benchmark before/after — measure token savings and latency reduction

## References

- Helium source: `/tmp/helium_demo/src/helium/`
- Helium examples: `/tmp/helium_demo/examples/`
- Helium benchmark: `/tmp/helium_demo/benchmark/`
- OV5 architecture: `OUROBOROS-V5.md`
- Related gap analysis: `mementum/knowledge/deep-searcher-vs-ov5-gaps.md`
