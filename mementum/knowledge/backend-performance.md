---
title: Backend Performance Analysis
status: active
category: analytics
tags: [backend, routing, ontology, experiments]
related: [project-facts, ontology-router]
depends-on: [gptel-auto-workflow-ontology-router]
---

# Backend Performance Analysis

## Dataset

- **1,204 experiments** analyzed
- **5 backends** with varying sample sizes
- **~200 hours** of experiment runtime
- **Analysis date**: 2026-05-21

## Overall Keep Rates

| Backend | Keep Rate | Total Experiments | Kept | Discarded |
|---------|-----------|-------------------|------|-----------|
| MiniMax | **20.5%** | 904 | 185 | 719 |
| DeepSeek | **19.0%** | 58 | 11 | 47 |
| CF-Gateway | **12.8%** | 78 | 10 | 68 |
| moonshot | **10.7%** | 28 | 3 | 25 |
| ~~DashScope~~ | ~~0.0%~~ | ~~17~~ | ~~0~~ | ~~17~~ |
| DashScope | *TBD* | 0 | 0 | 0 |

*DashScope model changed `glm-5` → `qwen3.6-plus` after 0% keep rate.*

## Key Findings

### 1. MiniMax Is the Baseline (20.5%)

- Accounts for **75% of all experiments**
- Consistent moderate performance
- Safe default for unknown targets

### 2. Category-Based Advantages

Routing uses **target categories**, not individual files. Categories derived from filename patterns:

#### :programming → DeepSeek

Targets: FSM, benchmarks, tests, retry, introspection, reasoning, code, compilation

| Representative Target | DeepSeek Keep Rate | MiniMax Keep Rate |
|----------------------|-------------------|-------------------|
| `gptel-ext-fsm.el` | **40.0%** | N/A |
| `gptel-benchmark-memory.el` | **33.3%** | N/A |
| `gptel-benchmark-tests.el` | **25.0%** | N/A |
| `gptel-ext-retry.el` | **25.0%** | N/A |
| `gptel-tools-introspection.el` | **20.0%** | N/A |

#### :tool-calls → MiniMax (default)

Targets: sandbox, bash, grep, glob, edit, apply, preview, programmatic tools
- No override — CF-Gateway data inconclusive (25% sandbox n=small, 17.6% tools-agent)
- MiniMax baseline (20.5%) is safer default until more data

| Representative Target | CF-Gateway Keep Rate | MiniMax Keep Rate |
|----------------------|---------------------|-------------------|
| `gptel-sandbox.el` | 25.0% (n=small) | **20.5%** (n=904) |
| `gptel-tools-agent.el` | 17.6% (n=small) | **20.5%** (n=904) |

#### :natural-language → DeepSeek

Targets: context, prompts, chat, conversation, text processing, streaming
- DeepSeek's reasoning strength applies to NL tasks
- No experimental data yet — using programming-category inference

#### :agentic → MiniMax (baseline)

Targets: agent orchestration, workflow, evolution, strategy, harness
- No override — uses ontology-reordered fallback
- MiniMax already first in default order

### 3. Sample Size Limitations

- DeepSeek/moonshot/CF-Gateway need **more samples** (<100 each)
- Confidence intervals are wide on small samples
- Exploration rate should stay at 15% to gather more data

## Routing Rules

### Default Rule
```
IF target NOT categorized
THEN use ontology-reordered fallback (by keep-rate)
```

### Category Override Rule
```
LET category = categorize(target)
IF category IN override-map AND override != nil
THEN preferred backend = override backend
     boost score to 9999 (first position)
```

### Exploration Rule
```
IF random() < 0.15 AND length(fallbacks) > 1
THEN swap top 2 backends
     (gathers data for comparison)
```

## Implementation

- `gptel-auto-workflow-ontology-router.el` — reorders `headless-subagent-fallbacks`
- Categories: `gptel-auto-workflow--categorize-target` (programming/tool-calls/natural-language/agentic)
- Overrides: `gptel-auto-workflow--category-backend-overrides`
- Category stats: `gptel-auto-workflow--get-category-performance-stats` (aggregates across all targets in category)
- Updated when ontology data confirms new patterns (≥3 experiments, ≥15% advantage)

## Token Savings

- Each discarded experiment: **~7,000 input + ~8,000 output = ~15,000 tokens**
- With prediction threshold at 0.15, low-confidence experiments are skipped
- Typical avoidance: **~15K tokens per skip**

## Action Items

- [ ] Monitor DashScope with `qwen3.6-plus` for 20+ experiments
- [ ] Increase DeepSeek samples on programming targets to confirm 40% rate
- [ ] Gather more CF-Gateway data on tool-call targets before overriding MiniMax default
- [ ] Consider adding moonshot advantage category if pattern emerges
- [ ] Recompute statistics monthly as sample sizes grow
- [ ] Add target→category mapping tests when new module types emerge

## Related

- `lisp/modules/gptel-auto-workflow-ontology-router.el` — routing implementation
- `mementum/knowledge/ontology-router.md` — router documentation
- `mementum/memories/dashscope-zero-keep-rate.md` — fix decision
