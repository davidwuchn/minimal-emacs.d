---
title: Helium-Inspired Caching Implementation
date: 2026-06-16
type: insight
tags: [helium, caching, performance, subagent, llm, intermediate-results]
---

# Helium-Inspired Caching Implementation

## What I Did

Implemented two new caching layers in OV5's prefix-cache module, inspired by Helium's three-level caching strategy:

1. **Response Cache**: Caches LLM responses for identical prompts within a run
2. **Intermediate Result Cache**: Caches expensive computations like target categorization

## Key Insights

1. **Helium's architecture is fundamentally different from OV5**:
   - Helium: DAG-based workflow model with typed operators
   - OV5: Linear FSM with pipeline phases
   - Helium: Local LLM servers with KV cache control
   - OV5: External APIs without direct KV cache access

2. **Three-level caching is the key pattern**:
   - Level 1: Prefix cache (stable prompt prefix) — already existed in OV5
   - Level 2: Response cache (identical LLM calls) — implemented
   - Level 3: Intermediate cache (expensive computations) — implemented

3. **Per-run isolation is critical**:
   - Caches must be cleared on run start/end
   - Prevents cross-run contamination
   - LRU eviction prevents unbounded growth

4. **Integration points matter**:
   - Response cache: wired into `my/gptel--run-agent-tool-with-timeout`
   - Intermediate cache: wired into `gptel-auto-workflow--categorize-target`
   - Both use generic APIs for extensibility

## Technical Details

### Response Cache
- Key: `(backend . model . prompt-sha1-hash)`
- Max size: 500 entries
- Excluded: `executor` agent (produces unique edits)
- Metrics: hits, misses, hit-rate

### Intermediate Cache
- Key: `(result-type . input-sha1-hash)`
- Max size: 1000 entries
- Generic API: `gptel-prefix-cache-with-intermediate`
- Current use: target categorization
- Metrics: hits, misses, hit-rate

## Test Coverage

- Response cache: 9 tests
- Intermediate cache: 8 tests
- All existing tests still pass (49 prefix-cache, 31 ontology-router, 50 subagent)

## Future Work

1. **Cache-aware scheduling**: Order subagent calls to maximize prefix reuse
2. **More intermediate result types**: Baseline quality scores, complexity metrics
3. **Speculative parallel branches**: Launch multiple hypotheses concurrently
4. **Monitor actual hit rates**: Measure real-world impact in pipeline runs

## Files Modified

- `lisp/modules/gptel-ext-prefix-cache.el`: Added response and intermediate cache implementations
- `lisp/modules/gptel-tools-agent-subagent.el`: Integrated response cache into subagent dispatch
- `lisp/modules/gptel-auto-workflow-ontology-router.el`: Integrated intermediate cache into categorization
- `tests/test-gptel-ext-prefix-cache.el`: Added 17 new tests

## References

- Helium source: `/tmp/helium_demo/`
- Helium paper: `helium-extended.pdf`
- Knowledge file: `mementum/knowledge/helium-caching-strategy.md`
