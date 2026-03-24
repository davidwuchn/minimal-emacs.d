# Autonomous Research Agent

## Status: active

## Related

- docs/auto-workflow.md
- mementum/memories/experiment-timeout-handling.md
- mementum/memories/llm-degradation-detection.md
- mementum/knowledge/tdd-patterns.md

## Content

### Pipeline

```
worktree → analyzer → executor → grader → benchmark → code-quality → comparator → decide
```

### Subagents

| Subagent | Function | Stage |
|----------|----------|-------|
| analyzer | `gptel-benchmark-analyze` | Pattern detection |
| executor | `gptel-benchmark-execute` | Code changes |
| grader | `gptel-benchmark-grade` | Quality validation |
| comparator | `gptel-benchmark-compare` | A/B decision |

### Decision Logic

```
combined = 70% * grader_score + 30% * code_quality_score
```

### Code Quality Scoring

```elisp
(gptel-benchmark--code-quality-score code)
;; => 0.0-1.0 (docstring coverage)
```

### LLM Degradation Detection

```elisp
(gptel-benchmark--detect-llm-degradation response expected-keywords)
;; => (:degraded-p t :reason "I apologize" :score 0.67)
```

Detects:
- Forbidden keywords (apologies, AI self-reference)
- Off-topic responses (missing expected keywords)

### Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `gptel-auto-experiment-time-budget` | 600s | Max time per experiment |
| `gptel-auto-experiment-grade-timeout` | 60s | Grading timeout |
| `gptel-auto-experiment-max-per-target` | 10 | Max experiments per file |
| `gptel-auto-experiment-no-improvement-threshold` | 3 | Stop after N no-improvements |

### TSV Output

```
experiment_id  target  hypothesis  score_before  score_after  code_quality  delta  decision
```

### Cron Schedule

```
2 AM  daily   - gptel-auto-workflow-run
4 AM  weekly  - gptel-mementum-weekly-job
5 AM  weekly  - gptel-benchmark-instincts-weekly-job
```

### Known Issues

1. **Test isolation** - Tests pass individually, fail together (stub pollution)
2. **API timeouts** - Experiments can exceed 600s budget

### Symbol

λ autonomous - self-improving code optimization