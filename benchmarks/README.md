# OV5 Benchmark System

The benchmark is the core of OV5's self-evolving and self-healing capabilities. It measures what the system learns, how it improves, and where it fails.

## What We Measure

| Metric | What It Means | How We Track |
|--------|--------------|--------------|
| **Keep-rate** | % of experiments that improve code | `results.tsv` column 8 (decision) |
| **Cost-per-kept** | USD spent per successful experiment | `results.tsv` column 31 (cost_usd) |
| **Effort level** | Reasoning depth (xhigh/high/medium/default) | `results.tsv` column 32 (effort_level) |
| **Duration** | Wall-clock time per experiment | `results.tsv` column 9 (duration) |
| **Backend efficiency** | Which model works best for which task | `results.tsv` columns 16, 27, 32 |

## Directory Structure

```
benchmarks/
├── README.md              # This file
├── skill-tests/           # Skill-specific test definitions
│   ├── clojure-expert.json
│   ├── elisp-expert.json
│   └── ...
└── workflow-tests/        # Agent workflow test definitions
    ├── code_agent.json
    ├── executor_agent.json
    └── plan_agent.json
```

## Task Format

Each task is a JSON file with:

```json
{
  "id": "unique-id",
  "name": "descriptive-name",
  "prompt": "The task for the agent",
  "expected_behaviors": ["What should happen"],
  "forbidden_behaviors": ["What should NOT happen"],
  "metadata": {
    "category": "code|research|analysis",
    "difficulty": "easy|medium|hard",
    "effort_level": "xhigh|high|medium|default"
  }
}
```

## Effort Level Configuration

Effort levels control reasoning depth and cost. Configured per-backend in `gptel-ext-backend-registry.el`:

| Backend | xhigh | high | medium | default |
|---------|-------|------|--------|---------|
| deepseek-v4-pro | "high" | "medium" | "low" | "low" |
| kimi-k2.6 | "high" | "medium" | "low" | "low" |
| qwen3.7-max | "high" | "medium" | "low" | "low" |

**Task-type defaults:**
- Executor/Grader/Reviewer → `high` (quality-critical)
- Analyzer/Researcher/Comparator → `default` (speed/cost optimized)

## Backend-Task Matrix

The benchmark reveals which backend is best for which task:

| Task Type | Best Backend | Effort | Cost/Task | Keep-Rate |
|-----------|-------------|--------|-----------|-----------|
| Executor (code changes) | MiniMax-M3 | default | ~$0.002 | 18% |
| Executor (complex) | deepseek-v4-pro | high | ~$0.04 | 8% |
| Grader | qwen3.7-max | high | ~$0.005 | 75% accuracy |
| Researcher | kimi-k2.6 | default | ~$0.008 | N/A |

## Running Benchmarks

```elisp
;; Run skill benchmark
(gptel-skill-benchmark-run "clojure-expert")

;; Run workflow benchmark
(gptel-workflow-run-benchmark "code_agent")

;; Run auto-workflow experiment (continuous improvement)
(gptel-auto-workflow-run-async)
```

## Self-Evolution Loop

```
Experiments → results.tsv → Parse → Analyze → Evolve
    ↑                                          ↓
    └──────────── Inject into prompts ─────────┘
```

1. **Observe**: Parse `results.tsv` for patterns (what works, what fails)
2. **Orient**: Identify high-signal keywords and anti-patterns
3. **Decide**: Generate improvement suggestions
4. **Act**: Inject learned patterns into next experiment prompts
5. **Feed Forward**: Commit learnings to git for cross-session memory

## Cost Efficiency

Based on DeepSWE benchmark data (May 2026):

| Model | Pass@1 | Cost/Pass | Our Keep-Rate | Our Cost/Kept |
|-------|--------|-----------|---------------|---------------|
| gpt-5.5 | 70% | $9.44 | N/A | N/A |
| gpt-5.4 | 56% | $7.82 | N/A | N/A |
| gpt-5.4-mini | 24% | $8.67 | N/A | ~$2-10 |
| kimi-k2.6 | 24% | $13.17 | N/A | ~$3-12 |
| deepseek-v4-pro | 8% | $52.75 | N/A | ~$4-16 |

**Key insight**: Our autonomous system achieves ~20% keep-rate at lower cost per kept experiment than single-shot problem solving.

## Continuous Improvement

The benchmark is not a one-time test. It runs continuously:

- **Every experiment** → logged to `results.tsv`
- **Every hour** → evolution cycle analyzes patterns
- **Every day** → self-healing detects broken evaluators
- **Every week** → instinct evolution commits learned patterns

The system gets smarter with every experiment. The benchmark is the feedback loop that makes self-evolution possible.
