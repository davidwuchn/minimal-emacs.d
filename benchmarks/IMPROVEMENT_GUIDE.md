# GPTel Skill Improvement Guide

## Quick Start

```elisp
;; Run a benchmark (interactive)
M-x gptel-skill-benchmark-run RET planning RET

;; Or programmatically
(gptel-skill-benchmark-run "planning")

;; View results
M-x gptel-skill-benchmark-show-results RET planning RET

;; View trends over time
M-x gptel-skill-benchmark-trend RET planning RET

;; Analyze results with analyzer agent
(gptel-skill-analyze-with-agent "planning")
```

## The Improvement Cycle

The skill improvement system uses existing agents (grader, analyzer, comparator) via RunAgent:

```
┌─────────────┐
│  BENCHMARK  │───▶ RunAgent(skill) → RunAgent(grader)
│  (Run tests)│
└─────────────┘
       │
       ▼
┌─────────────┐
│   ANALYZE   │───▶ RunAgent(analyzer)
│ (Find issues)│
└─────────────┘
       │
       ▼
┌─────────────┐
│   COMPARE   │───▶ RunAgent(comparator)
│ (Measure Δ) │
└─────────────┘
       │
       ▼
┌─────────────┐
│   IMPROVE   │───▶ Manual or automated fixes
│  (Iterate)  │
└─────────────┘
```

## Agents Used

| Agent | Purpose | Input | Output |
|-------|---------|-------|--------|
| `grader` | Evaluate outputs | eval_metadata.json, outputs/ | grading.json |
| `analyzer` | Find patterns | benchmark.json, iteration-N/ | findings, recommendations |
| `comparator` | A/B comparison | output_a/, output_b/, prompt | winner, reasoning |

## Feedback Points

| Stage | Feedback Type | Logged Data |
|-------|--------------|-------------|
| FB1 | Test execution | Pass/fail per test |
| FB2 | Pattern analysis | Flaky tests, systematic failures |
| FB3 | Grading | SCORE: X/Y, evidence |
| FB4 | Comparison | Delta, winner, dimensions |
| FB5 | Historical | Trend over time |

## Metrics and Targets

### Key Metrics

| Metric | Formula | Target |
|--------|---------|--------|
| Pass Rate | passed/total × 100 | ≥85% |
| Improvement Delta | new_score - old_score | +15% per cycle |
| Edge Case Coverage | edge_cases_passed/edge_cases_total | 100% |
| Flaky Test Rate | flaky_tests/total_tests | <5% |

### Version Targets

| Version | Pass Rate | Edge Cases | Negative Tests |
|---------|-----------|------------|----------------|
| v1.0 (baseline) | 100% (easy) | 0/3 | 0/2 |
| v1.1 (target) | ~60% (hard) | 3/3 | 2/2 |
| v1.2 (after fixes) | ~85% | 3/3 | 2/2 |

## Troubleshooting

### Common Issues

**Problem:** Benchmark returns empty results
- **Cause:** Test file not found
- **Fix:** Verify `assistant/evals/skill-tests/{skill}.json` exists

**Problem:** RunAgent fails
- **Cause:** gptel backend not configured
- **Fix:** Check `gptel-backend` and API keys

**Problem:** Grading fails
- **Cause:** grader agent not responding correctly
- **Fix:** Check `*Messages*` for LLM response format

**Problem:** Analysis shows all tests flaky
- **Cause:** Non-deterministic skill output
- **Fix:** Add more specific assertions, reduce ambiguity

### Getting Help

1. Check `benchmarks/feedback.log` for detailed logs
2. Run `gptel-skill-benchmark-trend` to see historical performance
3. Review `BENCHMARK_NUCLEUS.md` for grading rubric

## Next Steps

After reading this guide:
1. Run your first benchmark
2. Review the analysis
3. Compare before/after
4. Document learnings
