---
title: "OpenMythos (Looped Transformers): Architecting OV5 as a Recurrent System"
status: open
category: research
tags: [architecture, recurrent-depth, looped-transformers, stability, convergence]
related: [research-attention-residuals-ov5, self-evolving-agent-research]
depends-on: []
---

# OpenMythos (Looped Transformers): Architecting OV5 as a Recurrent System

## Paper: OpenMythos — Reconstruction of Claude Mythos (RDT)

**Kye Gomez, 2026. 13.7k stars, 3.1k forks.**

### Core Insight

Claude Mythos is suspected to be a **Recurrent-Depth Transformer (RDT)** — also called a Looped Transformer. Rather than stacking hundreds of unique layers, a subset is recycled and run multiple times per forward pass. Same weights. More loops. Deeper thinking. All reasoning happens silently in continuous latent space — no chain-of-thought token output.

### Key Architecture

```
Input → [Prelude P] → [Recurrent Block R] (looped T times) → [Coda C] → Output
```

**Recurrence update rule:** `h_{t+1} = A·h_t + B·e + Transformer(h_t, e)`
- `h_t` = hidden state after loop t
- `e` = encoded input from Prelude, injected at every loop
- `A, B` = learned injection parameters

### Critical Mechanisms

1. **Stability via spectral radius**: Enforce ρ(A) < 1 by parameterizing A as negative diagonal matrix. Every convergent run maintains this; every divergent run violates it.

2. **Input injection prevents drift**: The original input e is re-injected at every loop, keeping the signal alive throughout recurrence.

3. **Latent thoughts as implicit CoT**: Each loop = one CoT step in continuous space. Multiple alternatives explored simultaneously (breadth-first search).

4. **Depth extrapolation**: Train on 5-hop reasoning → succeeds at 10-hop by running more loops at inference.

5. **Loop index embedding**: RoPE-like embedding differentiates function across iterations. Same weights, different computational phases.

6. **Overthinking & adaptive halting**: ACT (Adaptive Computation Time) dynamically decides when to stop looping. Easy inputs exit early.

7. **MoE for breadth**: Fine-grained experts + shared experts. Router selects different experts per token and per loop iteration.

8. **Parameter reuse via LoRA**: Small rank-r adaptation per loop iteration. Bridges weight-tying (efficient) and distinct layers (expressive).

9. **Continuous depth-wise batching**: Different tokens exit at different depths. 2-3x inference throughput improvement.

10. **Scaling laws**: Optimal training scales looping and data together. Looped model at 770M matches 1.3B fixed-depth transformer.

---

## OV5 Comparison

### The Analogy: OV5 is a Recurrent-Depth System

OV5's pipeline IS a recurrent block:

```
Select Target → [Research P] → [Experiment R] (looped N times) → [Learn C]
```

Each experiment cycle is a "loop" through the same recurrent process. The system runs the same operations (build prompt, execute, grade, decide) on different targets.

### Gap 1: No Stability Guarantee (vs Spectral Radius)

**OpenMythos**: Enforces ρ(A) < 1 mathematically. The system cannot diverge by construction.
**OV5**: Keep-rate is probabilistic. There's no mathematical guarantee that experiments converge to better code. The system can and does enter death spirals (same target, same strategy, 0% keep rate).

**Fix**: Add a stability metric analogous to spectral radius. Compute per-target or per-category convergence scores. When keep-rate drops below threshold with stable strategy, force diversification (already exists via strategy rotation, but could be mathematically guaranteed).

### Gap 2: No Input Re-Injection (vs Signal Preservation)

**OpenMythos**: Re-injects original input e at every loop to prevent drift.
**OV5**: The original experiment intent (user-defined quality gates, business rationale) can drift across cycles. The context database stores rationale but doesn't systematically re-inject it into each experiment.

**Fix**: Add "input re-injection" — at the start of each experiment cycle, re-assert the original quality gates and business rationale. Use the context database's `:business-rationale` field as the "e" signal that gets re-injected.

### Gap 3: No Learned Halting (vs Adaptive Computation)

**OpenMythos**: ACT dynamically decides when to stop looping. Hard problems get more compute; easy ones exit early.
**OV5**: Uses fixed experiment budgets per target. No learned signal for "this target is as good as it's going to get."

**Fix**: Add per-target convergence detection. When Δ(keep_rate) < threshold for N consecutive experiments, halt experiments on that target. Already partially implemented via category saturation detection but could be more explicit.

### Gap 4: No Depth Extrapolation (vs Train-5-Test-10)

**OpenMythos**: Trained on 5-hop, succeeds on 10-hop by running more loops at inference.
**OV5**: Experiments are atomic. The system doesn't learn to handle increasingly complex, multi-step changes from simpler training.

**Fix**: Multi-step experiment chains. Let the system learn to compose experiments: experiment A refactors module X, experiment B (dependent on A) adds feature Y. Train on 1-step changes, extrapolate to N-step.

### Gap 5: No Loop Differentiation (vs Index Embedding)

**OpenMythos**: RoPE-like loop index embedding makes each iteration functionally distinct despite shared weights.
**OV5**: Experiments are largely identical in structure (build prompt, execute, grade). No mechanism to make the Nth experiment on a target fundamentally different from the 1st.

**Fix**: Add "experiment index embedding" — inject metadata about experiment position into the prompt. "This is experiment #3 on this target. Previous 2 were discarded. Focus on a DIFFERENT approach." This already partially exists via strategy rotation.

### Gap 6: No Parameter Reuse Across Experiments (vs LoRA)

**OpenMythos**: LoRA modules allow per-iteration adaptation of shared weights.
**OV5**: pi Synthesis propagates strategies across similar files, but there's no per-target adaptation of the experiment strategy. Each target uses the same strategy template.

**Fix**: Per-target strategy refinement. After N experiments on a target, adapt the strategy based on what's worked. Already partially exists via target-specific model preference.

---

## What OV5 Could Learn

### 1. Mathematical Stability Guarantee

Add convergence scoring analogous to spectral radius:
- Compute per-target "stability score" based on keep-rate trajectory
- When score crosses threshold, auto-halt experiments
- When score drops, force diversification

### 2. Systematic Input Re-Injection

Add context re-injection to experiment prompts:
- Before each experiment, inject the original quality gates as constraints
- Inject business rationale from context database
- "You are optimizing module X. The goal is: [original intent]. Previous attempts: [summary]."

### 3. Learned Halting Criterion

Add adaptive experiment stopping:
- Per-target: monitor keep-rate convergence
- Per-category: monitor improvement trajectory
- When Δ(quality) / Δ(experiments) → 0, halt

### 4. Multi-Step Experiment Chains

Enable experiment composition:
- Experiment A: refactor module X
- Experiment B: (depends on A) add feature Y
- Experiment C: (depends on B) test feature Y with integration tests
- Train on single-step, extrapolate to multi-step at inference

### 5. Experiment Index Embedding

Inject positional signal into experiments:
- "Experiment #N on target X. Previously: [outcomes]. Now try: [different approach]."
- Use N as a signal for how much exploration vs exploitation to apply
- Loop index determines strategy selection (early = explore, late = exploit)

---

## The Big Insight: OV5 IS a Looped Transformer

OV5's architecture maps cleanly to the RDT structure:

| RDT Component | OV5 Analog | Current State |
|--------------|-----------|---------------|
| Prelude | Research + Analysis | ✓ Initial context building |
| Recurrent Block | Experiment cycle (×N) | ✓ Runs multiple experiments |
| Coda | pi Synthesis + Learn | ✓ Post-experiment synthesis |
| Input injection | Context database | ⚠ Stored but not re-injected |
| Spectral radius | Keep rate stability | ⚠ Probabilistic, not guaranteed |
| ACT halting | Experiment budget | ⚠ Fixed budget, not adaptive |
| Loop index | Strategy rotation | ⚠ Partial (3-strikes rule) |
| MoE routing | Smart backend routing | ✓ Multi-backend with failover |
| LoRA adaptation | pi Synthesis | ✓ Strategy propagation |
| Depth batching | Experiment cadence | ⚠ Fixed per-cycle, not per-target |

**The key realization**: OV5 doesn't need to implement RDT mechanics literally. But the RDT architecture provides a DESIGN LANGUAGE for thinking about how OV5 should work:

- Experiments should be RECURRENT, not INDEPENDENT
- Each cycle should RE-INJECT the original intent
- Quality should be STABLE by construction, not probabilistic
- Compute should be ADAPTIVE per target, not uniform
- Depth should EXTRAPOLATE — the system should get better at complex problems as it runs more cycles

---

## Implementation Roadmap (Hypothetical)

### Phase 1: Stability Scoring

Add `gptel-auto-workflow--compute-stability`:
- Per-target keep-rate trajectory
- Convergence score (Δ keep-rate over last N experiments)
- Auto-halt when converged; auto-diversify when diverging

### Phase 2: Context Re-Injection

Modify prompt building to re-inject original intent:
- Add `:original-intent` field to experiment context
- Inject before each experiment cycle
- Track drift from original intent

### Phase 3: Adaptive Experiment Budget

Replace fixed experiment counts with adaptive:
- Per-target convergence detection
- Easy targets: fewer experiments
- Hard targets: more experiments
- Overall cycle budget: allocates experiments where they matter most

### Phase 4: Multi-Step Experiment Chains

Add experiment dependency graph:
- Prerequisite experiments before dependent ones
- Topological ordering of experiment execution
- Depth extrapolation: train on simple chains, test on complex

### Phase 5: Experiment Index Embedding

Add positional metadata to experiment prompts:
- Experiment index within batch
- Previous outcomes summary
- Strategy selection based on index (early=explore, late=exploit)

---

## Key Takeaways

1. **OV5 IS a recurrent system** — the RDT architecture provides a formal language for describing and improving it
2. **Stability should be guaranteed, not hoped for** — ρ(A) < 1 in OV5 terms = keep_rate > 0 with bounded divergence
3. **Input must be re-injected** — original intent should flow through every experiment cycle
4. **Compute should be adaptive** — easy targets get fewer experiments, hard targets get more
5. **Depth should extrapolate** — the system should get better at complex problems over time
6. **The loop index matters** — experiments at different positions in the cycle should behave differently

---

## References

- OpenMythos: https://github.com/kyegomez/OpenMythos
- Parcae: Scaling Laws for Stable Looped Language Models (arXiv:2604.12946)
- Universal Transformers (arXiv:1807.03819)
- Reasoning with Latent Thoughts (arXiv:2502.17416)
- Relaxed Recursive Transformers (arXiv:2410.20672)
- OV5 architecture: OUROBOROS-V5.md
