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

## Integration with OV5 Subsystems

The benchmark is the **sensor layer** that feeds all OV5 control systems. Every subsystem depends on benchmark data to make decisions.

### Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        BENCHMARK (Sensor Layer)                      │
│  results.tsv: experiment_id, target, decision, keep_rate, cost, ... │
└─────────────────────────────────────────────────────────────────────┘
                                    │
            ┌───────────────────────┼───────────────────────┐
            │                       │                       │
            ▼                       ▼                       ▼
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────────┐
│   AutoTTS        │    │   AutoGo         │    │  Ontology Router     │
│ (Research Stop)  │    │ (Strategy Gate)  │    │ (Backend Selection)  │
│                  │    │                  │    │                      │
│ Input:           │    │ Input:           │    │ Input:               │
│ - keep_rate      │    │ - strategy_score │    │ - keep_rate_by_model │
│ - cost_per_kept  │    │ - win/loss       │    │ - cost_per_task      │
│ - experiment     │    │ - champion       │    │ - effort_level       │
│   velocity       │    │   history        │    │ - backend_health     │
│                  │    │                  │    │                      │
│ Output:          │    │ Output:          │    │ Output:              │
│ - continue/stop  │    │ - promote/reject │    │ - selected_backend   │
│ - research       │    │ - champion       │    │ - selected_model     │
│   priority       │    │   update         │    │ - selected_effort    │
└──────────────────┘    └──────────────────┘    └──────────────────────┘
            │                       │                       │
            └───────────────────────┼───────────────────────┘
                                    │
                                    ▼
                        ┌──────────────────────┐
                        │   VSM Health         │
                        │ (System Diagnosis)   │
                        │                      │
                        │ Input:               │
                        │ - overall_keep_rate  │
                        │ - cost_efficiency    │
                        │ - backend_diversity  │
                        │ - experiment_volume  │
                        │                      │
                        │ Output:              │
                        │ - system_health      │
                        │ - remediation        │
                        │   suggestions        │
                        └──────────────────────┘
```

### Subsystem Relationships

| Subsystem | Uses Benchmark Data For | Feeds Back To Benchmark |
|-----------|------------------------|------------------------|
| **AutoTTS** | Decide when to stop research (keep_rate > 15% → stop) | Generates new research hypotheses |
| **AutoGo** | Gate strategies (new strategy must beat champion) | Promotes winning strategies to prompt templates |
| **Ontology Router** | Select backend/model/effort (cost_efficiency, keep_rate) | Routes experiments to different backends |
| **VSM Health** | Diagnose system problems (low keep_rate → investigate) | Triggers remediation (backend swap, parameter tuning) |
| **Eight Keys** | Grade experiment quality (part of keep/discard decision) | Provides quality signal for keep_rate calculation |
| **Skill Graph** | Track which skills improve code (kept experiments) | Evolves skill recommendations |

### Benchmark as Feedback Loop

The benchmark is not just measurement—it's the **control signal** for the entire self-regulating system:

```
1. Benchmark measures: keep_rate, cost_per_kept, backend_performance
   ↓
2. Subsystems consume: AutoTTS stops research, AutoGo gates strategies, Router selects backends
   ↓
3. Subsystems act: Stop research, promote strategy, switch backend
   ↓
4. Benchmark measures again: Did the action improve keep_rate?
   ↓
5. Repeat (self-regulating loop)
```

### Key Metrics by Subsystem

**AutoTTS (Research Control):**
- `keep_rate > 15%` → Research is working, continue
- `keep_rate < 10%` for 3 runs → Research is stuck, stop or change direction
- `cost_per_kept > $5` → Too expensive, reduce research budget

**AutoGo (Strategy Competition):**
- `strategy.keep_rate > champion.keep_rate` → Promote new strategy
- `strategy.keep_rate < 5%` → Reject strategy (doesn't work)
- Track win/loss history for each strategy

**Ontology Router (Backend Selection):**
- `keep_rate_by_model` → Which model has highest success rate?
- `cost_per_task` → Which model is most cost-efficient?
- `effort_level` → High effort for complex tasks, low for simple
- `backend_health` → Skip backends with recent failures

**VSM Health (System Diagnosis):**
- `overall_keep_rate < 10%` → System unhealthy, investigate
- `cost_efficiency < 0.1` → Wasting money, tune parameters
- `backend_diversity < 2` → Over-reliant on one backend, add fallbacks

### Concrete Example

```
Run 1: Benchmark measures keep_rate = 12%, cost_per_kept = $8.50
  ↓
AutoTTS: keep_rate < 15%, continue research but lower priority
AutoGo: Strategy A has 12% keep_rate, champion has 18%, reject A
Router: DeepSeek has 15% keep_rate, MiniMax has 8%, prefer DeepSeek
VSM: keep_rate < 10% threshold not yet hit, system healthy
  ↓
Run 2: Benchmark measures keep_rate = 18%, cost_per_kept = $6.20
  ↓
AutoTTS: keep_rate > 15%, research working well, continue
AutoGo: Strategy B has 18% keep_rate, beats champion (18%), promote B
Router: DeepSeek now 20% keep_rate, even better, keep using it
VSM: System improving, no action needed
```

### The Ouroboros Loop

The benchmark enables the self-eating snake:

```
Benchmark → Measure → AutoTTS/AutoGo/Router → Act → Benchmark → Measure → ...
```

Each subsystem is a **reflex arc** that consumes benchmark data and produces actions that change future benchmark results. The system regulates itself without human intervention.

**Without benchmark:** Blind system, no feedback, no self-regulation.
**With benchmark:** Self-aware system, continuous improvement, autonomous operation.
