---
name: token-efficiency
description: Controls prompt compression and section inclusion based on experiment results
version: 1.0
updated: 2026-05-05 08:02
---

# Token Efficiency

This skill auto-evolves based on experiment results.
It controls prompt compression and section inclusion.

## Token Efficiency Analysis

Correlation between prompt size and experiment success:

- **Average prompt size (kept):** 17104 chars
- **Average prompt size (discarded):** 17513 chars
- **Success rate per 1000 chars (kept):** 0.34%
- **Discarded rate per 1000 chars:** 0.61%
- **Optimal prompt range:** Shorter prompts work better (17104 vs 17513 chars)

**Prompt Compression Config:**
- topic-knowledge-max-chars: 800
- compress-behavior: auto
- compress-trigger: prompt exceeds optimal size

## Section A/B Test Results

Which prompt sections improve outcomes:

- **all**: 22% success (58/259 experiments)

**Section Inclusion Config:**
- default: include all
- a-b-test-enabled: t
- omit-rate: 0.2
- min-samples: 10

