---
title: "Attention Residuals: Lessons for OV5 Experiment Weighting"
status: open
category: research
tags: [attention, learning, synthesis, weighted-aggregation, transformer]
related: [self-evolving-agent-research, research-planning-graph-plansearch-ov5-gaps]
depends-on: []
---

# Attention Residuals: Lessons for OV5 Experiment Weighting

## Paper: Attention Residuals (arXiv:2603.15031)

**Kimi Team (Moonshot AI), March 2026**

### Core Insight

Standard PreNorm residual connections accumulate all layer outputs with **fixed unit weights**. This causes uncontrolled hidden-state growth with depth and progressively dilutes each layer's contribution. Attention Residuals (AttnRes) replaces this with **softmax attention** over preceding layer outputs, allowing each layer to selectively aggregate earlier representations with **learned, input-dependent weights**.

### Key Mechanisms

1. **Standard residuals**: Fixed unit weights → hidden-state growth → dilution
2. **Full AttnRes**: Softmax attention over all preceding layers → learned, input-dependent selection
3. **Block AttnRes**: Partitions layers into blocks, attends over block-level reps (efficiency)
4. **Cache + two-phase computation**: Reduces memory/communication overhead
5. **Scaling law consistency**: Improvement is consistent across model sizes
6. **Uniform outputs/gradients**: More uniform distribution across depth → better downstream

### Results

- Consistent improvement across all model sizes (scaling law experiments)
- Better downstream performance on all evaluated tasks
- Integrated into Kimi Linear (48B total / 3B activated) on 1.4T tokens
- More uniform output magnitudes and gradient distribution across depth

---

## OV5 Comparison

### The Analogy: Experiments as Transformer Layers

OV5's pipeline is a sequence of layers:
```
Research → Analyze → Execute → Verify → Learn
```

Each "layer" (experiment) produces output that should inform future layers. But currently, OV5 treats each experiment as an independent unit — knowledge is stored separately, and synthesis uses fixed rules.

### Gap 1: No Inter-Experiment Attention

**AttnRes idea**: Each layer selectively aggregates preceding layers with learned weights.
**OV5 state**: Knowledge synthesis uses fixed rules (e.g., "≥3 memories on same topic → synthesize"). No learned, content-dependent weighting of which experiments are most relevant.

**Analogy**: OV5's standard residuals are like PreNorm with unit weights — every experiment contributes equally to the ontology, regardless of quality, relevance, or impact.

### Gap 2: Fixed-Weight Accumulation in Synthesis

**AttnRes idea**: Softmax attention computes importance scores based on content.
**OV5 state**: Mementum synthesis uses confidence scores from the synthesizer LLM, but these are post-hoc labels, not learned attention weights over the experiment space.

**Analogy**: OV5 knows which experiments "passed" (kept) vs "failed" (discarded), but it doesn't compute a learned importance score for how much each experiment should contribute to ongoing learning.

### Gap 3: No Depth-Wise Selection

**AttnRes idea**: Each layer attends to the most relevant preceding layers, not all of them.
**OV5 state**: When building experiment context, OV5 uses recent experiments by default. There's no mechanism to "attend to" a specific past experiment because it's relevant to the current target, not because it's recent.

**Analogy**: OV5 has a "recency bias" (fixed decay) rather than "content-based attention" (learned relevance).

### Gap 4: No Uniformity Across the Experiment Sequence

**AttnRes insight**: Standard residuals create uneven distribution of contributions across depth.
**OV5 state**: Early experiments (baseline establishment) may be underweighted compared to recent experiments. The ontology may drift toward recent patterns while forgetting foundational ones.

**Analogy**: OV5 doesn't measure or optimize for "uniform contribution" across its experiment sequence. Some periods may dominate the ontology while others are diluted out.

---

## What OV5 Could Learn

### 1. Weighted Knowledge Synthesis

Instead of aggregating memories with fixed rules (≥3 → synthesize), use a learned weighting:
- Compute attention-like scores for each memory based on relevance to current context
- Weight more relevant memories higher in synthesis
- Allow "irrelevant" memories to be down-weighted even if numerous

**Implementation**: Add an attention mechanism to mementum synthesis that computes relevance scores for each memory before synthesis.

### 2. Selective Experiment Context

When building experiment context (prior results, patterns):
- Attend to the most relevant past experiments, not just the most recent
- Compute relevance scores based on target similarity, strategy overlap, and outcome patterns
- Use learned weights, not fixed time-based decay

**Implementation**: Replace `previous-results` (simple list) with a weighted attention over historical experiments. Similar to how `gptel-auto-experiment--hypothesis-diversity` computes similarity for plan diversity, compute relevance for context building.

### 3. Recency-Aware Weighting with Content-Based Override

- Default: recent experiments have higher weight (like standard residuals)
- Override: relevant older experiments get boosted weight (like attention)
- Balance: learned α that trades off recency vs relevance per target category

**Implementation**: Add `gptel-auto-workflow--compute-experiment-relevance` that returns (1 - α) × recency + α × relevance where α is learned per category.

### 4. Uniform Contribution Monitoring

- Track how much each experiment "era" (e.g., weekly batches) contributes to current ontology
- Detect when the system is "forgetting" early patterns
- Re-weight to maintain uniform contribution distribution

**Implementation**: Add depth-uniformity metric to monitoring agent. Alert when ≥70% of ontology comes from ≤20% of the experiment timeline.

---

## Block AttnRes Analogy: Batch-Level Synthesis

Block AttnRes partitions layers into blocks and attends over block-level representations. In OV5, this suggests:

- **Batch-level synthesis**: Instead of synthesizing per-memory (fine-grained), synthesize per-batch (block-level)
- **Reduced overhead**: Attend over batch summaries (block reps) rather than individual memories
- **Preserved gains**: Most of the benefit with much less computation

**Implementation**: After each experiment batch, compute a batch summary (like a block representation). When synthesizing, attend over batch summaries rather than individual experiment records.

---

## Implementation Roadmap (Hypothetical)

### Phase 1: Experiment Relevance Scoring

Add `gptel-auto-workflow--compute-experiment-relevance`:
- Jaccard similarity on target/hypothesis tokens (like plan diversity)
- Category overlap
- Outcome pattern similarity
- Temporal proximity

### Phase 2: Weighted Context Building

Modify context building to use relevance scores:
- Replace simple `previous-results` list with weighted attention
- Boost relevant older experiments
- Down-weight irrelevant recent experiments

### Phase 3: Uniformity Monitoring

Add depth-uniformity metric:
- Track contribution distribution across experiment timeline
- Alert on drift/forgetting
- Auto-reweight to maintain balance

### Phase 4: Block-Level Synthesis

Implement batch-level knowledge synthesis:
- Batch summaries after each pipeline run
- Attend over batch summaries for synthesis
- Reduced overhead, preserved gains

---

## Key Takeaways

1. **Fixed weight aggregation causes dilution** — OV5's uniform treatment of all experiments dilutes important signals
2. **Content-based attention > fixed rules** — Learned relevance weights would improve knowledge synthesis
3. **Depth uniformity matters** — OV5 should track and maintain uniform contribution across its experiment timeline
4. **Block-level aggregation is efficient** — Batch summaries would reduce synthesis overhead while preserving gains
5. **The analogy is structural, not superficial** — OV5's experiment pipeline IS a transformer-like architecture. Each experiment IS a layer. The attention residual insight applies directly.

---

## References

- AttnRes: arXiv:2603.15031 (Kimi Team, March 2026)
- OV5 architecture: OUROBOROS-V5.md
