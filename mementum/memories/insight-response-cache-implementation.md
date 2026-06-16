---
title: "Response cache implementation (Helium-inspired)"
date: 2026-06-16
tags: [helium, caching, response-cache, subagent, performance]
symbol: 💡
---

# Response cache implementation (Helium-inspired)

Implemented result-level caching for subagent LLM calls, inspired by Helium's three-level caching strategy.

## Key design decisions

1. **Cache key**: `(backend-name . model . prompt-hash)` — uses SHA1 hash of prompt (first 16 chars) for efficient lookup
2. **LRU eviction**: When cache exceeds `gptel-prefix-cache-response-cache-max-size` (default 500), oldest entries are evicted
3. **Per-run isolation**: Cache is cleared on run start/end — no cross-run contamination
4. **Executor exclusion**: Executor subagent is excluded from caching (produces unique edits per call)
5. **Callback wrapping**: On cache miss, wraps callback to store response before passing to original callback

## Integration points

- `gptel-ext-prefix-cache.el`: Added response cache state, lookup/store functions, LRU eviction, stats tracking
- `gptel-tools-agent-subagent.el`: Modified `my/gptel--run-agent-tool-with-timeout` to check cache before dispatch
- `gptel-prefix-cache-on-run-start`: Clears response cache
- `gptel-prefix-cache-on-run-end`: Logs stats and clears cache
- `gptel-prefix-cache-export-metrics`: Includes response cache hit/miss/size in metrics

## Test coverage

Added 9 new tests to `test-gptel-ext-prefix-cache.el`:
- `test-response-cache-compute-key` — key generation
- `test-response-cache-store-and-lookup` — basic store/retrieve
- `test-response-cache-miss` — missing key returns nil
- `test-response-cache-clear` — reset state
- `test-response-cache-lru-eviction` — LRU eviction when full
- `test-response-cache-with-response-cache-hit` — cache hit serves immediately
- `test-response-cache-with-response-cache-miss` — cache miss wraps callback
- `test-response-cache-stats` — statistics reporting
- `test-response-cache-disabled` — respects enabled flag

All 41 prefix-cache tests pass.

## Expected impact

- **Token savings**: Identical prompts (e.g., same target analyzed multiple times) skip API calls entirely
- **Latency reduction**: Cache hits return immediately (no network round-trip)
- **Cost reduction**: Fewer API calls = lower cost per run

## Future enhancements

- Add temperature check — only cache for temperature==0 (deterministic) calls
- Add per-agent-type cache size limits
- Add cache hit rate to monitoring agent metrics
