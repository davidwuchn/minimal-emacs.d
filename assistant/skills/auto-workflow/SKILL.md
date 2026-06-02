---
name: auto-workflow
description: Orchestrates automated code improvement through hypothesis-driven experimentation and self-evolution
version: 1.1
evolve-script: generate_directive.py
level: compound
molecules: [benchmark-improver, evolution-patterns, skill-eval, sandbox-profiles]
---
metadata:
  evolution-stats:
    total-experiments: 870

# Auto-Workflow

This skill suite orchestrates automated code improvement through systematic experimentation and self-evolution.

## Skill Architecture

The auto-workflow system consists of coordinated sub-skills:

### Core Pipeline
- **RESEARCHER** — Analyzes targets, proposes hypotheses, checks repositories
- **DIRECTIVE** — Strategic planning, target selection, resource allocation
- **prompt-template** — Structured experiment prompt construction

### Quality Control
- **validation-pipeline** — Validates experiment outcomes against quality gates
- **agent-behavior** — Defines agent behavior patterns for experiment execution

### Evolution
- **token-efficiency** — *(Moved to mementum/knowledge/)* Learned compression settings from experiment outcomes

## Activation

Auto-workflow is triggered by the cron pipeline or manual invocation:

```
(auto-workflow bootstrap [target-path])
```

## Self-Evolution

This skill auto-improves through:
1. **Experiment logging** — Each run generates trace data
2. **Outcome analysis** — Statistical controller learns from kept vs discarded results
3. **Skill refinement** — Sub-skills updated based on performance data

## Configuration

- Cron schedule: `0 23,3,7,11,15,19 * * *`
- Pipeline lock: `var/tmp/cron/pipeline.lock`
- Trace storage: `var/tmp/research-traces/`
- Controller config: `var/tmp/researcher-controller.json`
