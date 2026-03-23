# OUROBOROS Gap Detection Workflow

## Insight

Gap detection compares research advice to project implementation using 4 methods: static analysis, benchmark thresholds, pattern compliance, and OUROBOROS alignment.

## Lambda

```
λ gap(x).    expected(x) ∧ ¬implemented(x)
             | documented(x) ∧ ¬tested(x)
             | benchmark(x) < threshold(x)
             | research_advice(x) ∧ ¬aligned(project, x)
```

## Methods

| Method | What It Checks | Example |
|--------|----------------|---------|
| Static Analysis | Files/functions exist | `skills-list` not defined |
| Benchmark Threshold | Score < threshold | 0.5 < 0.8 threshold |
| Pattern Compliance | Documented vs tested | Pattern in protocol but no test |
| OUROBOROS Alignment | Research vs project | Missing progressive disclosure |

## Integration Points

- `gptel-benchmark-instincts.el` — Record gaps as low-φ instincts
- `gptel-benchmark-evolution.el` — Feed gaps to evolution cycle
- `gptel-workflow-benchmark.el` — Add gap tests to benchmark suite

## Current Gaps (2026-03-23)

| Gap | Severity | Status |
|-----|----------|--------|
| Progressive Disclosure | Medium | ❌ Missing |
| Skills Standardization | Medium | ⚠️ Partial |
| Immutable File Definitions | Low | ⚠️ Partial |
| Architectural Safety | Low | ⚠️ Partial |

## Resolution Flow

```
Detect → Record (φ=0.5) → Evolution → Implement → Verify → Update (φ=0.8+)
```

## Source

- `docs/OUROBOROS.md` — Full documentation
- `gptel-ouroboros-advice` — Const defining expected items

## Captured

2026-03-23 — From OUROBOROS research implementation session