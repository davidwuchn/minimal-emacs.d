---
title: "OpenRouter Fusion vs OV5 Researcher: Multi-Model Research Gaps"
status: active
category: architecture
tags: [fusion, multi-model, research, panel, consensus, DRACO, benchmark]
related: [helium-vs-ov5-gaps, auto-research-vs-ov5-gaps, deep-searcher-vs-ov5-gaps]
depends-on: []
---

# OpenRouter Fusion vs OV5 Researcher: Multi-Model Research Gaps

**Date**: 2026-06-16
**Source**: https://openrouter.ai/blog/announcements/fusion-beats-frontier/
**Author**: Brian Thomas, OpenRouter (6/12/2026)

## Fusion's Core Innovation

OpenRouter Fusion synthesizes results from **multiple models in parallel** to surpass individual frontier model performance. One API call dispatches to a panel of models, a judge model produces structured analysis (consensus, contradictions, blind spots), and a final answer is grounded in that analysis.

### Key Benchmark Results (DRACO, 100 deep research tasks)

| Configuration | Score | Cost |
|---|---|---|
| **Fusion: Fable 5 + GPT-5.5** (judge: Opus 4.8) | **69.0%** | High |
| Fusion: Opus 4.8 + GPT-5.5 + Gemini 3.1 Pro | 68.3% | High |
| Fusion: Opus 4.8 + GPT-5.5 | 67.6% | Medium-High |
| **Fusion: Opus 4.8 + Opus 4.8** (self-fusion) | **65.5%** | Medium |
| Solo: Claude Fable 5 | 65.3% | High |
| **Fusion: Budget panel** (Gemini 3 Flash + Kimi K2.6 + DeepSeek V4 Pro) | **64.7%** | Low |
| Solo: DeepSeek V4 Pro | 60.3% | Low |
| Solo: GPT-5.5 | 60.0% | Medium |
| Solo: Claude Opus 4.8 | 58.8% | High |

### Three Key Insights

1. **Panels consistently outperform individuals** — Fable 5 + GPT-5.5 (69.0%) > Fable 5 alone (65.3%)
2. **Budget panels can surpass frontier models** — Budget panel (64.7%) > GPT-5.5 (60.0%) and Opus 4.8 (58.8%)
3. **Self-fusion gives significant boost** — Opus 4.8 + Opus 4.8 (65.5%) > solo Opus 4.8 (58.8%), a 6.7-point jump from synthesis alone

## Fusion Architecture

```
User Prompt
    │
    ▼
┌─────────────────────────────────────┐
│  PANEL DISPATCH (parallel)          │
│  ┌─────────┐ ┌─────────┐ ┌──────┐ │
│  │ Model A │ │ Model B │ │Model C│ │
│  │ + search│ │ + search│ │+search│ │
│  └────┬────┘ └────┬────┘ └───┬────┘ │
└───────┼───────────┼──────────┼──────┘
        │           │          │
        ▼           ▼          ▼
┌─────────────────────────────────────┐
│  JUDGE MODEL (structured analysis)  │
│  - Consensus points                 │
│  - Contradictions                   │
│  - Partial coverage                 │
│  - Unique insights                  │
│  - Blind spots                      │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  FINAL ANSWER (grounded in          │
│  structured analysis)               │
└─────────────────────────────────────┘
```

## OV5 Researcher Architecture (Current)

```
Periodic Trigger
    │
    ▼
┌─────────────────────────────────────┐
│  BUILD RESEARCH PROMPT              │
│  - Load SKILL.md template           │
│  - Substitute variables             │
│  - Select research variant          │
│  - Inject AutoTTS strategy          │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  SINGLE MODEL DISPATCH (MiniMax-M3) │
│  ┌─────────────────────────────┐    │
│  │ Researcher (one model)      │    │
│  │ + WebSearch + WebFetch      │    │
│  └─────────────┬───────────────┘    │
│                │                     │
│  AutoTTS: STOP/CONTINUE/BRANCH/     │
│           WIDEN/CUT (multi-turn)    │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  DIGEST (pass-through or LLM)       │
│  → research-findings.edn            │
│  → Analyzer → Experiments           │
└─────────────────────────────────────┘
```

## Architecture Comparison

| Dimension | Fusion | OV5 Researcher |
|-----------|--------|----------------|
| **Model count** | Panel of 2-3+ models in parallel | Single model (MiniMax-M3) |
| **Synthesis** | Judge model: consensus, contradictions, blind spots | Sequential accumulation, no cross-model verification |
| **Self-fusion** | Yes — same model ×2 gives 6.7pt boost | Never runs same prompt twice |
| **Budget strategy** | Budget panels beat frontier models | Backend registry has cost data but unused for panels |
| **Benchmark** | DRACO (100 tasks, ~39 criteria, 4 categories) | Heuristic scoring (URL count, structure, length) |
| **Contamination prevention** | Domain exclusion lists for eval rubrics | None |
| **Judge model** | Separate model evaluates panel responses | Same model self-evaluates |
| **Cross-model consensus** | Core innovation — structured analysis | Holographic consensus exists but only for backend routing |
| **Multi-turn** | Single-shot panel dispatch | AutoTTS multi-turn controller (5 decisions) |
| **Strategy evolution** | Static panel composition | AutoTTS controller evolution, champion league |
| **Cost tracking** | Cost per task benchmarked | Token economics tracked per experiment |

## OV5 Researcher Strengths (Fusion Lacks)

- **AutoTTS multi-turn controller** — 5 decisions (STOP/CONTINUE/BRANCH/WIDEN/CUT) with EMA confidence tracking. Fusion is single-shot.
- **Strategy champion league** — Research strategies compete per ontology category. Fusion uses static panel composition.
- **Controller design agent** — LLM writes controller decision rules, validated on held-out traces. Fusion has no self-improving controller.
- **Trace replay cache** — Offline evaluation with zero LLM calls. Fusion requires live API calls for every evaluation.
- **Mementum knowledge synthesis** — Cross-session memory with git-based persistence. Fusion has no persistent memory.
- **Ontology-driven gap analysis** — Research priorities driven by experiment ontology gaps. Fusion is topic-agnostic.
- **Provider failover** — Automatic backend switching on empty results. Fusion has no failover.
- **Doom loop detection** — Detects and breaks repetitive research patterns. Fusion has no loop detection.

## Highest-Leverage Gaps for OV5

### Gap 1: Multi-Model Research Panel
**Problem**: OV5 dispatches research to a single model (MiniMax-M3). Fusion showed panels consistently outperform individuals by 3-10 points.
**Fusion solution**: Dispatch to 2-3+ models in parallel, fuse with judge model.
**OV5 implementation**: Create `gptel-auto-workflow-research-fusion.el`:
- `research-fusion-dispatch` — send prompt to panel of models in parallel
- `research-fusion-judge` — judge model produces structured analysis (consensus, contradictions, blind spots)
- `research-fusion-synthesize` — final answer grounded in structured analysis
- Panel composition: use backend registry to select diverse models (not just highest health)

### Gap 2: Self-Fusion (Same Model ×2)
**Problem**: OV5 never runs the same research prompt through the same model twice. Fusion showed 6.7-point boost from self-fusion alone.
**Fusion solution**: Run same prompt twice through same model, synthesize differences.
**OV5 implementation**: Add to `research-fusion-dispatch`:
- `research-fusion-self-pair` — run same prompt twice through current backend
- Different reasoning paths, different tool calls, different source selections
- Synthesize differences via judge model
- Lowest-cost fusion: no additional model diversity needed

### Gap 3: Budget Panel Strategy
**Problem**: OV5's backend registry tracks cost per model but doesn't use it for research panel composition. Fusion showed budget panel (64.7%) beats frontier solo models.
**Fusion solution**: Compose panel from budget models (Gemini 3 Flash + Kimi K2.6 + DeepSeek V4 Pro).
**OV5 implementation**: Add to `research-fusion-dispatch`:
- `research-fusion-budget-panel` — select 3 budget models from backend registry
- Cost constraint: panel cost ≤ 1.5× single frontier model cost
- Diversity constraint: models from different providers
- Track cost-per-finding in research trace

### Gap 4: Structured Consensus Analysis
**Problem**: OV5 accumulates findings sequentially with no cross-model verification. Fusion's judge produces structured analysis: consensus points, contradictions, partial coverage, unique insights, blind spots.
**Fusion solution**: Judge model reads every panel response, produces structured analysis.
**OV5 implementation**: Create judge prompt template:
```
## Structured Analysis
### Consensus Points
[Findings all models agree on]
### Contradictions
[Findings that conflict between models]
### Partial Coverage
[Topics only some models covered]
### Unique Insights
[Novel findings from individual models]
### Blind Spots
[What no model covered — research gaps]
```

### Gap 5: Research Benchmark (DRACO-like)
**Problem**: OV5 uses heuristic scoring (URL count, structure, length). Fusion uses DRACO with ~39 weighted criteria across 4 categories.
**Fusion solution**: DRACO benchmark: Factual Accuracy (~20 criteria), Breadth & Depth (~9), Presentation Quality (~6), Citation Quality (~5).
**OV5 implementation**: Create `gptel-auto-workflow-research-benchmark-draco.el`:
- Define 20-30 research tasks spanning OV5's ontology categories
- Weighted criteria per task (factual accuracy, breadth, citations, actionability)
- Judge model grades per-criterion, 3 independent times
- Track scores in World Store for strategy evolution

### Gap 6: Contamination Prevention
**Problem**: Fusion discovered models finding grading rubrics online. OV5 has no contamination prevention.
**Fusion solution**: Exclude benchmark-related domains from web search/fetch.
**OV5 implementation**: Add to researcher dispatch:
- `research-fusion-excluded-domains` — list of domains to exclude from web search
- Auto-detect: if researcher finds its own eval criteria, flag contamination
- Track contamination events in research trace

## Implementation Priority

1. **Self-fusion** (Gap 2) — Lowest effort, proven 6.7pt boost. Just run same prompt twice.
2. **Multi-model panel** (Gap 1) — Core Fusion capability. Parallel dispatch + judge.
3. **Structured consensus** (Gap 4) — Judge prompt template. Works with any panel.
4. **Budget panel** (Gap 3) — Cost-aware panel composition from backend registry.
5. **Research benchmark** (Gap 5) — DRACO-like eval for research quality tracking.
6. **Contamination prevention** (Gap 6) — Domain exclusion for eval integrity.

## Strategic Insight

Fusion proves that **synthesis > selection** for research tasks. The synthesis step itself adds 6.7 points even with identical models. OV5's AutoTTS controller optimizes **when to stop/continue/branch** but never asks **whether multiple perspectives would improve the answer**.

The key insight: OV5 already has the infrastructure for multi-model dispatch (backend registry, subagent infrastructure, parallel execution). The missing piece is the **fusion layer** — parallel dispatch, structured analysis, and consensus synthesis.

**Integration path**: Add fusion as a research variant in the existing champion league. `fusion-panel` competes against `deep-external`, `own-repos-first`, etc. Champion league selects the best variant per ontology category. This preserves OV5's strategy evolution while adding multi-model capability.

## References

- Fusion blog post: https://openrouter.ai/blog/announcements/fusion-beats-frontier/
- DRACO paper: https://arxiv.org/abs/2602.11685
- Fusion API docs: https://openrouter.ai/docs/guides/features/server-tools/fusion
- OV5 researcher: `assistant/agents/researcher.md`
- OV5 strategic daemon: `lisp/modules/strategic-daemon-functions.el`
- OV5 research orchestration: `lisp/modules/gptel-auto-workflow-strategic.el`
