---
name: token-efficiency
description: Controls prompt compression and section inclusion based on experiment results
version: 1.0
updated: 2026-05-08 20:11
---
metadata:
  evolution-stats:
    total-experiments: 512
    last-evolution: 2026-05-08 20:11

---

# Token Efficiency

This skill auto-evolves based on experiment results.
It controls prompt compression and section inclusion.

## Token Efficiency Analysis

Correlation between prompt size and experiment success:

- **Average prompt size (kept):** 18064 chars
- **Average prompt size (discarded):** 18809 chars
- **Success rate per 1000 chars (kept):** 0.58%
- **Discarded rate per 1000 chars:** 1.36%
- **Optimal prompt range:** Shorter prompts work better (18064 vs 18809 chars)

**Prompt Compression Config:**
- topic-knowledge-max-chars: 800
- compress-behavior: auto
- compress-trigger: prompt exceeds optimal size

## Section A/B Test Results

Which prompt sections improve outcomes:

- **all**: 21% success (105/512 experiments)

**Section Inclusion Config:**
- default: include all
- a-b-test-enabled: t
- omit-rate: 0.2
- min-samples: 10


## Evolved Weights

Based on analysis of experiment results.

| Key | Weight | Discrimination | Avg (Success) | Avg (Failure) |
|-----|--------|----------------|---------------|---------------|


## Evolved Validation Rules

Based on analysis of failed experiments.

| Rule | Severity | Frequency | Check |
|------|----------|-----------|-------|


## Evolved Tool Profiles

Based on analysis of 0 experiments.

| Tool | Level | Success Rate | Experiments |
|------|-------|--------------|-------------|


## Evolved Improvement Effectiveness

Based on analysis of 105 kept and 407 discarded experiments.

| Element | Effectiveness | Keep Rate | Improvement Rate | Total | Kept |
|---------|---------------|-----------|------------------|-------|------|
| Control (Earth) | highly-effective | 25% | 9% | 204 | 50 |
| Intelligence (Fire) | highly-effective | 25% | 12% | 8 | 2 |
| Coordination (Metal) | moderately-effective | 12% | 2% | 57 | 7 |
| Identity (Water) | moderately-effective | 13% | 4% | 45 | 6 |
| Operations (Wood) | highly-effective | 23% | 7% | 111 | 25 |

### Top Words in Successful Hypotheses

These words appear most frequently in hypotheses that were kept:

- **will**: 76 times
- **adding**: 69 times
- **prevent**: 47 times
- **explicit**: 42 times
- **when**: 41 times
- **runtime**: 40 times
- **errors**: 40 times
- **clarity**: 40 times
- **validation**: 37 times
- **cache**: 31 times

### Prioritize These Improvement Types

- Control (Earth) (25% keep rate, 50 kept out of 204)
- Intelligence (Fire) (25% keep rate, 2 kept out of 8)
- Coordination (Metal) (12% keep rate, 7 kept out of 57)
- Identity (Water) (13% keep rate, 6 kept out of 45)
- Operations (Wood) (23% keep rate, 25 kept out of 111)


## Evolved Error Patterns

Based on analysis of experiment errors.

| Pattern | Category | Action | Frequency | Regex |
|---------|----------|--------|-----------|-------|

