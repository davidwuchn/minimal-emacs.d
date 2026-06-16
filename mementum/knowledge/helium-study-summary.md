# Helium Study & Implementation Summary

**Date**: 2026-06-16  
**Status**: ✅ Complete

## Objective

Study Helium (https://github.com/mlsys-io/helium_demo), compare with OV5, identify gaps, and implement improvements.

## What is Helium?

Helium is a workflow-aware LLM serving framework from MLSys that optimizes agentic workflows through:
- DAG-based workflow modeling with typed operators
- Three-level caching strategy (prompt, KV, intermediate results)
- Cache-aware scheduling (CAS) to maximize prefix reuse
- Speculative parallel branch execution

## Key Findings

### Helium vs OV5 Architecture

| Aspect | Helium | OV5 |
|--------|--------|-----|
| Workflow model | DAG of typed operators | Linear FSM (pipeline phases) |
| LLM backend | Local servers (vLLM, SGLang) | External APIs (Anthropic, OpenAI) |
| Caching | Three-level (prompt, KV, intermediate) | Prefix cache only (before this work) |
| Scheduling | Cache-aware (CAS) | Sequential dispatch |
| Self-improvement | None | Core feature (ontology learning, self-healing) |
| Quality gates | Simple pass/fail | 7 gates + complexity gate |
| Memory | In-memory caches | Datahike World Store + mementum |

### Highest-Leverage Gaps Identified

1. **Response caching** — Cache identical LLM calls within a run
2. **Intermediate result materialization** — Cache expensive computations (e.g., target categorization)
3. **Cache-aware scheduling** — Order dispatches to maximize prefix sharing (future work)
4. **Speculative parallel branches** — Launch hypotheses concurrently (future work)

## Implementation

### 1. Response Cache ✅

**File**: `lisp/modules/gptel-ext-prefix-cache.el`  
**Integration**: `lisp/modules/gptel-tools-agent-subagent.el`

- Caches LLM responses keyed by `(backend . model . prompt-hash)`
- LRU eviction (max 500 entries)
- Per-run isolation (cleared on run start/end)
- Excludes `executor` agent (produces unique edits)
- Metrics exported to `var/metrics/prefix-cache-stats.json`

**Tests**: 9 new tests in `tests/test-gptel-ext-prefix-cache.el`

### 2. Intermediate Result Cache ✅

**File**: `lisp/modules/gptel-ext-prefix-cache.el`  
**Integration**: `lisp/modules/gptel-auto-workflow-ontology-router.el`

- Caches expensive computations (target categorization)
- Keyed by `(result-type . input-hash)`
- LRU eviction (max 1000 entries)
- Per-run isolation
- Generic API: `gptel-prefix-cache-with-intermediate`

**Tests**: 8 new tests in `tests/test-gptel-ext-prefix-cache.el`

### 3. Metrics Export ✅

Both caches export metrics:
- Hits, misses, hit-rate
- Cache size
- Exported to `var/metrics/prefix-cache-stats.json`

## Test Results

```
Full unit test suite: 3266 tests
- Expected: 3177 passed
- Skipped: 89
- Unexpected: 0 ✅

Specific test suites:
- Prefix-cache: 49 tests (41 original + 8 intermediate) ✅
- Response cache: 9 tests ✅
- Intermediate cache: 8 tests ✅
- Ontology-router: 31 tests ✅
- Subagent: 50 tests ✅
```

## Expected Impact

1. **Token savings**: Identical prompts skip API calls entirely
2. **Latency reduction**: Cache hits return immediately (no network round-trip)
3. **Cost reduction**: Fewer API calls per run
4. **CPU reduction**: Reduced redundant categorization computations

## Documentation

- **Knowledge file**: `mementum/knowledge/helium-caching-strategy.md`
- **Memory file**: `mementum/memories/insight-helium-caching-implementation.md`
- **State update**: `mementum/state.md` (session note added)

## Future Work

1. **Cache-aware scheduling**: Order subagent calls to maximize prefix reuse
2. **More intermediate result types**: Baseline quality scores, complexity metrics
3. **Speculative parallel branches**: Launch multiple hypotheses concurrently
4. **Monitor actual hit rates**: Measure real-world impact in pipeline runs
5. **KV cache integration**: If/when OV5 moves to local LLM servers

## Files Modified

1. `lisp/modules/gptel-ext-prefix-cache.el` — Added response and intermediate cache implementations
2. `lisp/modules/gptel-tools-agent-subagent.el` — Integrated response cache into subagent dispatch
3. `lisp/modules/gptel-auto-workflow-ontology-router.el` — Integrated intermediate cache into categorization
4. `tests/test-gptel-ext-prefix-cache.el` — Added 17 new tests
5. `mementum/state.md` — Added session note
6. `mementum/knowledge/helium-caching-strategy.md` — Created knowledge file
7. `mementum/memories/insight-helium-caching-implementation.md` — Created memory file

## Conclusion

Successfully studied Helium, identified key gaps, and implemented two of the four highest-leverage improvements:
- ✅ Response cache (Gap 1)
- ✅ Intermediate result materialization (Gap 2)
- ⏸ Cache-aware scheduling (Gap 3 — future work)
- ⏸ Speculative parallel branches (Gap 4 — future work)

All tests pass. No regressions. Ready for deployment.
