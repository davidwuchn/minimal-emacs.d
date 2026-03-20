# Benchmark Results Directory

This directory stores benchmark results for GPTel skills and workflows, including Eight Keys rubric scores.

## Structure

```
benchmarks/
├── <skill>-results.json              # Skill benchmark results
├── <skill>-history.json              # Skill historical trend data
├── workflows/
│   ├── <workflow>-results.json       # Workflow benchmark results
│   └── <workflow>-history.json       # Workflow historical trend data
└── feedback.log                      # Improvement feedback log
```

## File Formats

### Benchmark Results JSON

```json
[
  {
    "test-id": "test-001",
    "output": "Skill output here",
    "grade": {
      "score": 8,
      "total": 10,
      "percentage": 80.0,
      "passed": true,
      "eight-keys": {
        "phi-vitality": 0.85,
        "fractal-clarity": 0.92,
        "epsilon-purpose": 1.0,
        "tau-wisdom": 0.75,
        "pi-synthesis": 0.80,
        "mu-directness": 0.95,
        "exists-truth": 0.88,
        "forall-vigilance": 0.70,
        "overall": 0.86
      },
      "eight-keys-summary": "..."
    },
    "timestamp": "2024-01-15 10:30:00"
  }
]
```

### Trend Data JSON

```json
[
  {
    "date": "2024-01-15",
    "version": "v1.1",
    "score": 85.5,
    "eight-keys-overall": 0.86
  }
]
```

## Usage

### Skill Benchmarks

- `gptel-skill-benchmark-run` - Run benchmarks with Eight Keys scoring
- `gptel-skill-benchmark-show-eight-keys` - View Eight Keys breakdown
- `gptel-skill-benchmark-trend` - Show skill trend over time

### Workflow Benchmarks

- `gptel-workflow-benchmark-run` - Run workflow benchmarks
- `gptel-workflow-benchmark-run-all` - Run all workflow benchmarks
- `gptel-workflow-benchmark-trend` - Show workflow trend analysis
- `gptel-workflow-benchmark-show-eight-keys` - View Eight Keys breakdown

### Auto-Evolve

- `gptel-benchmark-evolve-with-improvement` - Run evolution + improvement cycle
- `gptel-benchmark-auto-improve-skill` - Auto-improve a skill
- `gptel-benchmark-auto-improve-workflow` - Auto-improve a workflow

## Eight Keys Scoring

Each skill output is scored against 8 philosophical principles:

| Key | Symbol | Focus |
|-----|--------|-------|
| **Vitality** | φ | Energy, growth, adaptive learning |
| **Clarity** | fractal | Explicit structure, testable definitions |
| **Purpose** | ε | Goal-directedness, actionable outcomes |
| **Wisdom** | τ | Foresight, planning before execution |
| **Synthesis** | π | Integration, holistic thinking |
| **Directness** | μ | Efficiency, no wasted effort |
| **Truth** | ∃ | Reality-based, evidence over assumptions |
| **Vigilance** | ∀ | Robustness, defensive constraints |

### Score Thresholds

- **Overall**: ≥ 70% (CI pass), ≥ 80% (excellent)
- **Per-Key**: ≥ 60% (minimum acceptable)

## Documentation

- [Benchmark Pipeline](../assistant/evals/benchmark-pipeline.md) - Complete pipeline documentation
- [Eight Keys Rubric](../assistant/evals/BENCHMARK_NUCLEUS.md) - Detailed Eight Keys criteria
- [Skill Tests](../assistant/evals/skill-tests/) - Test definitions for each skill
