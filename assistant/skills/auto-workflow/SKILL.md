---
name: token-efficiency
description: Controls prompt compression and section inclusion based on experiment results
version: 1.0
updated: 2026-05-05 09:00
---

# Token Efficiency

This skill auto-evolves based on experiment results.
It controls prompt compression and section inclusion.

## Token Efficiency Analysis

Correlation between prompt size and experiment success:

- **Average prompt size (kept):** 17125 chars
- **Average prompt size (discarded):** 17547 chars
- **Success rate per 1000 chars (kept):** 0.36%
- **Discarded rate per 1000 chars:** 0.64%
- **Optimal prompt range:** Shorter prompts work better (17125 vs 17547 chars)

**Prompt Compression Config:**
- topic-knowledge-max-chars: 800
- compress-behavior: auto
- compress-trigger: prompt exceeds optimal size

## Section A/B Test Results

Which prompt sections improve outcomes:

- **all**: 23% success (62/268 experiments)

**Section Inclusion Config:**
- default: include all
- a-b-test-enabled: t
- omit-rate: 0.2
- min-samples: 10

