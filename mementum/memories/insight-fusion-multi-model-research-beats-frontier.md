---
title: "Fusion multi-model research beats frontier solo"
date: 2026-06-16
tags: [fusion, multi-model, research, panel, consensus, DRACO]
symbol: 💡
---

# Fusion multi-model research beats frontier solo

OpenRouter Fusion (6/12/2026) dispatches research prompts to a **panel of models in parallel**, then a judge model produces structured analysis (consensus, contradictions, blind spots). Key results on DRACO benchmark (100 deep research tasks):

- **Fable 5 + GPT-5.5 fused = 69.0%**, vs Fable 5 alone = 65.3%
- **Budget panel** (Gemini 3 Flash + Kimi K2.6 + DeepSeek V4 Pro) = 64.7%, beats GPT-5.5 (60.0%) and Opus 4.8 (58.8%)
- **Self-fusion** (Opus 4.8 × 2) = 65.5%, vs solo = 58.8% — **6.7pt boost from synthesis alone**

## OV5 gaps identified

1. **Single-model research** — OV5 uses one model per session; Fusion uses 2-3+ in parallel
2. **No self-fusion** — Running same prompt twice gives 6.7pt boost; OV5 never does this
3. **No structured consensus** — Fusion judge produces: consensus, contradictions, blind spots; OV5 accumulates sequentially
4. **No research benchmark** — Fusion uses DRACO (39 criteria, 4 categories); OV5 uses heuristic scoring (URL count, length)
5. **No contamination prevention** — Fusion excludes eval domains from search; OV5 has none

## Key insight
Synthesis > selection for research. The synthesis step itself adds value even with identical models. OV5 has the infrastructure (backend registry, subagent dispatch) — missing piece is the fusion layer.

## Implementation priority
Self-fusion first (lowest effort, proven boost), then multi-model panel, then structured consensus judge.
