---
title: Graphify Deep Dive #3 — Build, Benchmark, Watch
date: 2026-05-17
symbol: 💡
---

# Graphify Deep Dive #3 — Build, Benchmark, Watch

## New Patterns Discovered

### build.py — 3-Layer Node Deduplication
1. **Within-file (AST)**: `seen_ids` set — one node per ID per file
2. **Between-file (NetworkX)**: `G.add_node()` overwrites on duplicate ID
3. **Semantic merge (skill)**: explicit `seen` set before graph construction

### benchmark.py — Token Reduction Measurement
- BFS from best-matching nodes, depth=3
- Reports per-question and average reduction ratio
- CHARS_PER_TOKEN = 4 (standard approximation)

### watch.py — File Change Auto-Sync
- **Two-tier response**: code changes → instant AST rebuild (no LLM); doc changes → notify user
- **Debounce**: 3s default
- **Flag file**: `graphify-out/needs_update` for pending semantic re-extraction
- Uses `watchdog` library

## What We Already Have (no gap)

| graphify Pattern | Our Equivalent |
|-----------------|---------------|
| Token reduction benchmark | `token-efficiency.md` — auto-evolves prompt compression based on experiment success rates (20665 avg kept vs 21656 discarded) |
| Node dedup | `research-insights` files are per-strategy, de-duped by safe-strategy slug |
| Auto-sync on changes | Cron pipeline (3-6 runs/day) |

## What's Missing

### 1. Watch Mode for Development
graphify's `--watch` auto-rebuilds on file changes. Our pipeline is cron-only.
**Gap**: No instant feedback loop during development. Changes take 4+ hours to be analyzed.

### 2. Two-Tier Analysis (code vs semantic)
graphify distinguishes code-only changes (instant AST rebuild) from semantic changes (needs LLM). Our self-evolution processes everything the same way.
**Gap**: All changes treated equally. Could prioritize by change type.

### 3. Prompt Token Benchmarking
graphify's `run_benchmark()` measures token savings. Our `token-efficiency.md` tracks correlation but doesn't measure raw token counts.
**Gap**: No per-experiment token measurement vs raw file size comparison.
