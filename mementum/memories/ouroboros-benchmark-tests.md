# OUROBOROS Benchmark Tests for Auto-Evolve

## Insight

No separate gap detection needed. Add benchmark tests for each research advice item, let existing auto-evolve detect failures.

## Simpler Approach

```
Research Advice → Benchmark Test → Auto-Evolve Detects → Improvement
```

Instead of:
```
Research Advice → Gap Detection System → Evolution
```

## Existing System Already Detects

| Module | Detection |
|--------|-----------|
| `gptel-benchmark-evolution.el` | Anti-patterns, low scores |
| `gptel-benchmark-auto-improve.el` | Benchmark failures |
| `gptel-benchmark-instincts.el` | Low φ = problem |

## Benchmark Tests to Add

1. **progressive-disclosure** — `skills-list`/`skill-view` exist
2. **skills-format-compliance** — agentskills.io format
3. **constraints-immutable-files** — Write protection works
4. **architectural-safety** — Timeouts, max-steps, sandbox

## Why No Separate System

Separate gap detection = redundant. Auto-evolve already:
- Runs benchmarks
- Detects failures (score < threshold)
- Records to instincts (φ = 0.5)
- Generates improvements

## Captured

2026-03-23 — Simplified from gap detection framework to benchmark tests