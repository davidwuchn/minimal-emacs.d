---
title: AutoTTS Firethering Article
status: active
category: research
tags: [autotts, test-time-scaling, ai-agents, research]
related: [autotts-arxiv-paper]
depends-on: []
---

# AutoTTS: Researchers Cut Inference Tokens by 70%

**Source:** https://firethering.com/autotts-ai-inference-test-time-scaling/
**Date:** 2026-05-12
**Author:** Mohit Geryani

## Key Points

- AutoTTS discovers test-time scaling strategies automatically using an AI agent
- Discovered "Confidence Momentum Controller" (CMC) reduces tokens by ~70% vs SC@64
- At β=0.5: matches accuracy at 30% of token cost
- At β=1.0: exceeds handcrafted baselines in 5/8 comparisons
- Discovery cost: $39.90 and 160 minutes
- Uses offline replay store (cached reasoning traces) - zero LLM calls during evaluation

## How It Works

1. **Offline trace collection:** Run model on questions, save reasoning paths, chunk into segments
2. **Agent writes controller code:** Claude Code agent writes Python controller that decides when to branch/continue/stop/probe/prune
3. **Replay evaluation:** Test controller against cached traces (no new LLM calls)
4. **Iterative refinement:** Agent gets accuracy, token cost, execution traces as feedback, rewrites controller
5. **Repeat until convergence**

## The Confidence Momentum Controller (CMC)

- **Trend-based stopping:** Uses EMA of pool confidence, stops only when high AND non-declining
- **Coupled width-depth control:** Widening linked to EMA delta - stagnation triggers new branches
- **Alignment-aware depth allocation:** Branches matching consensus get more compute
- **Conservative abandonment:** Branches cut only after persistent deviation, keeping >= 2 alive

## Integration Relevance

This article explains AutoTTS in accessible terms. The framework is directly applicable to our researcher system:
- We already have multi-turn research with controller decisions (STOP/CONTINUE/BRANCH/CUT)
- We can adapt the CMC's momentum-based confidence tracking for our research quality estimation
- The beta parameterization gives us a clean way to trade off exploration vs exploitation
- The replay-store concept matches our trace-based learning approach

## Action Items

- [ ] Adapt CMC's EMA confidence tracking to research controller
- [ ] Implement beta parameterization for research turn budget allocation
- [ ] Add alignment-aware depth allocation (favor sources producing good results)
- [ ] Create replay evaluation pipeline for research strategies
