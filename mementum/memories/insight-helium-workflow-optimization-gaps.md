---
title: "Helium workflow optimization gaps"
date: 2026-06-16
tags: [helium, caching, scheduling, workflow-optimization]
symbol: 💡
---

# Helium workflow optimization gaps

Studied helium_demo (MLSys paper on workflow-aware LLM serving). Key insight: agent workflow performance is dominated by LLM call latency, so caching and cache-aware scheduling are the most effective optimizations.

## Three-level caching strategy
1. **Prompt cache** (result-level): LRU cache for identical prompts (temperature==0)
2. **KV cache** (prefix-level): Precompute KV states for common prefixes
3. **Intermediate result reuse**: Cache and reuse partial outputs via CacheFetchOp

## Cache-aware scheduling (CAS)
Builds scheduling tree from radix tree of prompt prefixes. Orders ops to maximize KV cache reuse by scheduling similar-prefix ops back-to-back.

## Highest-leverage gaps for OV5
1. **Prompt prefix caching** — Cache identical subagent prompts across experiments in same run
2. **Intermediate result materialization** — Persist research findings per-run for reuse
3. **Cache-aware scheduling** — Order subagent dispatches to maximize prefix sharing
4. **Speculative parallel branches** — Launch candidate hypotheses concurrently

## Strategic insight
Helium optimizes **within a single workflow run** (caching, scheduling, deduplication). OV5 optimizes **across workflow runs** (ontology learning, self-healing, monitoring). Integration opportunity: add helium's within-run optimizations to OV5's existing across-run learning for both short-term and long-term memory.

## Implementation priority
Start with prompt prefix caching (lowest effort, highest impact). Add `gptel-ext-prefix-cache.el` with per-run LRU cache keyed by `(backend . model . prompt-hash)`.
