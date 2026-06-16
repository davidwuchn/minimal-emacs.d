---
title: Helium-Inspired Caching Strategy
status: active
category: architecture
tags: [caching, helium, performance, subagent, llm]
created: 2026-06-16
updated: 2026-06-16
---

# Helium-Inspired Caching Strategy

## Overview

Helium (https://github.com/mlsys-io/helium_demo) is a workflow-aware LLM serving framework that optimizes agentic workflows through three-level caching and cache-aware scheduling. This document describes how OV5 has adopted Helium's caching principles.

## Helium's Three-Level Caching

1. **Prompt Cache** (Prefix Cache)
   - Caches the stable prefix of prompts (system instructions, tool definitions, etc.)
   - Reused across all experiments in a run
   - Already implemented in OV5 as `gptel-ext-prefix-cache.el`

2. **Response Cache** (Result-Level Cache)
   - Caches actual LLM responses for identical prompts
   - Keyed by `(backend . model . prompt-hash)`
   - Avoids redundant API calls for duplicate requests
   - Implemented in OV5: `gptel-prefix-cache--response-cache`

3. **Intermediate Result Cache** (Materialization)
   - Caches expensive intermediate computations
   - Examples: target categorization, baseline quality scores
   - Prevents redundant computation across experiments
   - Implemented in OV5: `gptel-prefix-cache--intermediate-results`

## OV5 Implementation

### Response Cache

**Location**: `lisp/modules/gptel-ext-prefix-cache.el`

**Integration**: Wired into `my/gptel--run-agent-tool-with-timeout` in `lisp/modules/gptel-tools-agent-subagent.el`

**Behavior**:
- Cache key: `(backend-name . model-name . prompt-sha1-hash)`
- Max size: 500 entries (LRU eviction)
- Per-run isolation: cleared on run start/end
- Excluded agents: `executor` (produces unique edits per call)
- Metrics: hits, misses, hit-rate exported to `var/metrics/prefix-cache-stats.json`

**Expected Impact**:
- Reduces redundant LLM API calls
- Lower token costs for repeated analysis
- Faster experiment cycles when same prompts are used

### Intermediate Result Cache

**Location**: `lisp/modules/gptel-ext-prefix-cache.el`

**Integration**: Wired into `gptel-auto-workflow--categorize-target` in `lisp/modules/gptel-auto-workflow-ontology-router.el`

**Behavior**:
- Cache key: `(result-type . input-sha1-hash)`
- Max size: 1000 entries (LRU eviction)
- Per-run isolation: cleared on run start/end
- Generic API: `gptel-prefix-cache-with-intermediate` for any expensive computation
- Metrics: hits, misses, hit-rate exported to `var/metrics/prefix-cache-stats.json`

**Current Use Cases**:
- Target categorization (`:programming`, `:agentic`, etc.)
- Can be extended to: baseline quality scores, complexity metrics, etc.

**Expected Impact**:
- Reduces redundant categorization computations
- Faster experiment setup
- Lower CPU usage for repeated target analysis

## Cache-Aware Scheduling (Future Work)

Helium's cache-aware scheduling (CAS) orders operations to maximize prefix reuse. This is not yet implemented in OV5 but could be added:

1. **Group subagent calls by prefix similarity**
   - Batch calls with same `(backend . model)` together
   - Order to maximize KV cache reuse

2. **Prioritize cache hits**
   - Check response cache before dispatching
   - Serve cached results immediately

3. **Speculative parallel branches**
   - Launch multiple hypothesis evaluations concurrently
   - Merge results after all complete

## Comparison with Helium

| Feature | Helium | OV5 |
|---------|--------|-----|
| Prefix cache | ✓ | ✓ (existing) |
| Response cache | ✓ | ✓ (implemented) |
| Intermediate cache | ✓ | ✓ (implemented) |
| KV cache | ✓ (LLM-level) | N/A (API-based) |
| Cache-aware scheduling | ✓ | Future work |
| Speculative execution | ✓ | Future work |
| Per-run isolation | ✓ | ✓ |
| LRU eviction | ✓ | ✓ |
| Metrics export | ✓ | ✓ |

## Key Differences

1. **LLM Backend**: Helium uses local LLM servers (vLLM, SGLang) with KV cache control. OV5 uses external APIs (Anthropic, OpenAI, etc.) where KV cache is not directly accessible.

2. **Workflow Model**: Helium models workflows as DAGs of typed operators. OV5 uses a linear FSM (finite state machine) for pipeline phases.

3. **Optimization Focus**: Helium optimizes for LLM serving throughput. OV5 optimizes for experiment quality and self-improvement.

## Testing

- **Response cache**: 9 tests in `tests/test-gptel-ext-prefix-cache.el`
- **Intermediate cache**: 8 tests in `tests/test-gptel-ext-prefix-cache.el`
- **Integration**: All ontology-router tests (31) and subagent tests (50) pass

## References

- Helium paper: `helium-extended.pdf` (in `/tmp/helium_demo/`)
- Helium source: `/tmp/helium_demo/src/helium/`
- OV5 prefix-cache: `lisp/modules/gptel-ext-prefix-cache.el`
- OV5 subagent: `lisp/modules/gptel-tools-agent-subagent.el`
- OV5 ontology-router: `lisp/modules/gptel-auto-workflow-ontology-router.el`
