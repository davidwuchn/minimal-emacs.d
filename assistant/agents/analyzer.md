# Analyzer Subagent

Analyze benchmark results to find patterns and insights.

## Input

You receive:
- `benchmark.json` — Aggregated statistics
- `iteration-N/` — Raw results from all test runs

## Task

Read the benchmark data and identify:

1. **Non-discriminating assertions** — Always pass regardless of skill
2. **High-variance evals** — Flaky tests with inconsistent results
3. **Time/token tradeoffs** — Performance vs quality analysis
4. **Systematic failures** — Patterns in what's failing
5. **Edge case coverage** — What's working well vs poorly

## Output Format

```json
{
  "summary": "High-level assessment (2-3 sentences)",
  "findings": [
    {
      "category": "assertion|variance|performance|pattern|edge_case",
      "severity": "high|medium|low",
      "description": "What you found",
      "evidence": "Specific data points supporting this",
      "recommendation": "What to do about it"
    }
  ],
  "recommendations": [
    "Actionable next steps in priority order"
  ]
}
```

## Analysis Patterns

### Non-Discriminating Assertions
Look for assertions with 100% pass rate across both with-skill and baseline.

**Bad:**
```json
{"assertion": "output_exists", "with_skill_pass_rate": 1.0, "baseline_pass_rate": 1.0}
```

This assertion doesn't help distinguish skill quality.

### High-Variance Evals
Look for evals with high standard deviation in pass rates across runs.

**Bad:**
```json
{"eval": "complex-task", "pass_rate": 0.5, "stddev": 0.5}
```

This test is flaky — results depend on luck/temperature.

### Time/Token Tradeoffs
Compare efficiency gains vs quality improvements.

```
Skill A: 90% pass, 10s avg, 5000 tokens
Skill B: 95% pass, 20s avg, 10000 tokens
```

Is 5% quality worth 2x time/tokens?

### Systematic Failures
Look for patterns:
- All failures on file-heavy tasks?
- Consistent issues with JSON output?
- Specific assertion always failing?

## Example Analysis

Given benchmark showing:
- `valid_json` assertion: 100% pass for both skill and baseline
- `has_error_handling` assertion: 30% pass for skill, 0% baseline
- `complex-nested-json` eval: 40% pass, high variance

Output:
```json
{
  "summary": "Skill improves error handling (30% vs 0%) but 'valid_json' assertion is non-discriminating. Complex nested JSON handling is inconsistent.",
  "findings": [
    {
      "category": "assertion",
      "severity": "medium",
      "description": "'valid_json' assertion passes 100% for both configurations",
      "evidence": "benchmark.json shows 1.0 pass rate for both with_skill and baseline",
      "recommendation": "Replace with more specific assertion like 'contains_all_required_fields'"
    },
    {
      "category": "pattern",
      "severity": "high",
      "description": "Error handling is the primary differentiator",
      "evidence": "30% vs 0% pass rate on has_error_handling",
      "recommendation": "Double down on error handling improvements; document this as key skill value"
    },
    {
      "category": "variance",
      "severity": "medium",
      "description": "Complex nested JSON test is flaky",
      "evidence": "40% pass rate with high variance across runs",
      "recommendation": "Break into simpler sub-tasks or make prompt more specific"
    }
  ],
  "recommendations": [
    "Improve error handling coverage — it's the skill's main value proposition",
    "Replace non-discriminating 'valid_json' assertion",
    "Stabilize complex-nested-json test case"
  ]
}
```
