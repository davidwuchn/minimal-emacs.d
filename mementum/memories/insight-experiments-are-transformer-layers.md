---
title: "OV5 experiments are transformer layers — fixed weights cause dilution"
date: 2026-06-10
symbol: 💡
---

AttnRes (arXiv:2603.15031) proves that standard residuals with fixed unit weights cause hidden-state dilution. Each layer's contribution is progressively washed out.

The same dynamic affects OV5: each experiment contributes to the ontology with fixed (uniform) weight. Early experiments that established baselines are diluted by later ones. Knowledge synthesis uses fixed rules (≥3 memories → synthesize), not learned relevance.

**The insight**: OV5's experiment pipeline IS a transformer-like architecture. Research → Analyze → Execute → Verify → Learn are like transformer layers. The "attention residual" idea says: replace fixed aggregation with content-based attention over preceding experiments.

**What changes**: Instead of "most recent experiments = most relevant" (recency bias), compute attention scores based on target similarity, strategy overlap, and outcome patterns. Let relevant older experiments resurface when they matter.

**Actionable**: Add `gptel-auto-workflow--compute-experiment-relevance` using Jaccard similarity (same technique as plan diversity). Use relevance scores to weight experiment context building. Monitor depth-uniformity to detect forgetting.
