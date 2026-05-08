---
name: token-efficiency
description: Controls prompt compression and section inclusion based on experiment results
version: 1.0
updated: 2026-05-08 12:28
---

# Token Efficiency

This skill auto-evolves based on experiment results.
It controls prompt compression and section inclusion.

## Token Efficiency Analysis

Correlation between prompt size and experiment success:

- **Average prompt size (kept):** 17833 chars
- **Average prompt size (discarded):** 18683 chars
- **Success rate per 1000 chars (kept):** 0.57%
- **Discarded rate per 1000 chars:** 1.34%
- **Optimal prompt range:** Shorter prompts work better (17833 vs 18683 chars)

**Prompt Compression Config:**
- topic-knowledge-max-chars: 800
- compress-behavior: auto
- compress-trigger: prompt exceeds optimal size

## Section A/B Test Results

Which prompt sections improve outcomes:

- **all**: 20% success (102/498 experiments)

**Section Inclusion Config:**
- default: include all
- a-b-test-enabled: t
- omit-rate: 0.2
- min-samples: 10

