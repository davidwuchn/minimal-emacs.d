---
title: "Verbum vs OV5: Transferable Innovation Gap Analysis"
status: open
category: research
tags: [verbum, ov5, gap-analysis, crystal-equation, statechart, score-matching, kronecker, quantization, reproducibility]
related: [verbum-audit-methodology, simmis-vs-ov5-gap-analysis, research-attention-residuals-ov5, self-evolving-agent-research, self-healing-architecture]
depends-on: [verbum-audit-methodology]
created: 2026-06-12
---

# Verbum vs OV5: Transferable Innovation Gap Analysis

## What verbum already contributed to OV5

Before the gaps: OV5 already absorbed verbum's operational surface:
- **KIBC taxonomy** — 15-axis operation classification (OUROBOROS-V5.md line 494)
- **Attention magnets** — φ, λ, ∀, ∃, ⊗, Δ, ∞ prime formal reasoning in prompts
- **Audit methodology** — register-matching, null testing, held-out eval, variance decomposition (verbum-audit-methodology.md)
- **VSM + mementum** — shared architecture with verbum

These are about what OV5 *consumes* from verbum. The gaps below are about what OV5 has *not yet absorbed* — verbum's deeper mathematical and engineering innovations.

---

## Gap Analysis

### Gap 1: No formal pipeline statechart (transferability: high)

**What verbum does:** Every model executes the same 2n-state absorbing Markov chain — n fire states (K,I,B,C) + n WHNF absorbing states. Halt probability, reduction length, and gradient derive from φ. The transition graph IS the model's computational identity.

**What OV5 lacks:** The 7-gate pipeline is described informally ("on failure: experiment discarded, pattern learned"). There is no formal statechart with transition probabilities, absorption modes, or throughput formulas. OV5 does not know the probability that an experiment entering gate 3 will emerge at gate 6, nor which gates jointly dominate keep-rate variance.

**Concrete suggestion:** Build `gptel-auto-workflow--pipeline-statechart`:
- Define 7 gate states + 1 absorption state (kept) + 1 rejection state (discarded)
- Track empirical transition probabilities from experiment TSV history
- Derive expected keep-rate as product of gate-pass probabilities
- Use the statechart to predict pipeline bottleneck shifts before they happen
- Monitor gate-transition drift: when P(3→4) drops, gate 3 is degrading before gate 5 sees it

**φ connection:** If the pipeline has n active gates (currently 7), test whether keep-rate upper bound follows a φ-related decay: `keep_rate_max ≈ φ^(−s)` where s = n/(n+1) = 7/8. This is testable in one cycle against experiment history.

---

### Gap 2: No per-stage quality metric preventing compensating errors (transferability: very high)

**What verbum does:** Score Matching Loss computes per-layer cosine similarity between student and teacher transformations. This prevents compensating errors — a bad layer-3 output can't be "fixed" by layer-5 overcorrection because each layer is scored independently. Derived from Global Trajectory Score Matching (Ramachandran & Sra, 2026). Outperforms CE-only by 35%.

**What OV5 lacks:** AI grading is holistic — a single score per experiment. The seven gates produce independent pass/fail decisions, but the grade is a scalar. OV5 cannot detect when a weak test-pass (gate 2) is "compensated for" by a strong AI review (gate 4), because the grade collapses everything into one number.

**Concrete suggestion:** Add per-gate score vectors to `gptel-auto-experiment--grade`:
- Instead of a single grade, emit a 7-dimensional score vector (one per gate)
- Track cosine similarity between expected gate-scores (from category baseline) and observed gate-scores
- When cosine_sim < 0.7: flag as "compensating error — one gate overcorrecting for another"
- This naturally extends the existing verbum-audit null-testing discipline into the grading plane

**Integration point:** `gptel-auto-experiment--grade` already returns a scalar. Extend it to also return a gate-score vector stored in the experiment TSV.

---

### Gap 3: No parameter-reduction law (transferability: medium-high)

**What verbum does:** The computing fraction s = n/(n+1), where n is combinator count, predicts eigenvalue ratios with <0.04% error. It is a universal parameter-reduction law: given n, you know the spectral structure without measuring it. No free parameters. No fitting.

**What OV5 lacks:** OV5 has many configurable parameters (complexity threshold, keep-rate floor, diversity target, 14-day decay half-life, gate count, backend count, strategy count). There is no formula predicting system quality from parameter count. Every threshold is set by heuristic or historical tuning, not derived.

**Concrete suggestion:** Search for an OV5 analogue of s = n/(n+1):
- If n = number of active backends, does keep-rate follow a predictable curve?
- If n = number of active gates, does pipeline throughput follow a φ-spaced decay?
- Test 2-3 candidate parameter-reduction laws against the TSV history. Report in a research memory.
- Even finding "no, OV5 parameters don't follow a simple law" is a useful null result — it tells us the pipeline is heteroskedastic and needs per-parameter tuning.

**Note:** This is the least certain gap. verbum's law works because LLM layers share gradient structure. OV5 gates are heterogeneous (test execution ≠ review ≠ routing). The law may not exist. Test, don't assume.

---

### Gap 4: No Kronecker factorization of performance matrices (transferability: high)

**What verbum does:** The 16×16 crystal cosine matrix factors exactly as S⊗J + D⊗F, with D_eigenvalue/S_eigenvalue = φ^(n/(n+1)). Reconstruction correlation: 0.99999996. This means the cross-zone interaction matrix has exactly two degrees of freedom: a shared substrate (S) and a zone-specific diagonal (D).

**What OV5 lacks:** OV5's semantic clustering uses a single similarity threshold (≥0.75). The strategy × backend × category performance matrix is a flat lookup table. There is no factorization that separates:
- What all strategies share (substrate-independent performance)
- What is strategy-specific (diagonal over-performance)

**Concrete suggestion:** Factor OV5's strategy x category performance matrix:
- Build matrix M[strategy, category] = mean keep-rate over last N experiments
- Attempt Kronecker factorization: M ≈ U ⊗ V (rank-1) → test reconstruction error
- If rank-1 holds well: all strategies perform similarly across categories (substrate dominates)
- If rank-1 fails: strategies are category-specific (diagonal matters) → this justifies per-category strategy selection
- Either outcome is actionable: it tells you whether to invest in strategy diversity or unify around a single strategy

**Integration point:** `gptel-auto-workflow--strategy-performance-matrix` already exists. Add `gptel-auto-workflow--factor-performance-matrix` as a periodic audit.

---

### Gap 5: No formal compute cycle mapped to pipeline phases (transferability: medium)

**What verbum does:** The compute cycle β = [0, 1, 1+φ, 2+φ] defines WHEN each combinator fires. The cycle spacing is φ-based, not linear. The quantization curves derive from the same β values.

**What OV5 lacks:** The pipeline has 10+ sequential phases (select → categorize → route → generate → test → grade → gate → review → merge → learn) but phase ordering is conventional, not derived. No formalism tests whether reordering phases or inserting φ-spaced pauses improves outcomes.

**Concrete suggestion:** Map OV5 phases to verbum's β cycle:
- β₀ = 0 → "select" (identity, no transformation yet)
- β₁ = 1 → "categorize + route" (first active combinator)
- β₂ = 1+φ → "generate + test" (compositional — the K→I→B→C sequence)
- β₃ = 2+φ → "grade + gate + review + merge" (WHNF absorption — result either kept or discarded)

Then test: do φ-spaced phase groupings explain variance in experiment outcomes better than linear groupings? Use the existing experiment TSV with phase-timing data.

---

### Gap 6: Weaker experimental reproducibility surface (transferability: very high, low engineering cost)

**What verbum does:** Every probe has a formal canonical form:
- **Probes:** JSON + gates specification
- **Results:** JSONL + logprobs.npz
- **Provenance:** meta.json with model revision, git SHA, lockfile hash
- **Spec artifacts:** OpenAPI schema, GBNF grammar
- Unified 903-probe measurement library

The key insight: reproducibility is not "we ran it again and it worked." It is "another researcher can reconstruct the exact computational environment and verify the claim." The git SHA + lockfile hash make this machine-checkable.

**What OV5 lacks:** OV5 has TSV results and `.sexp` sidecars but no per-experiment provenance record. Missing:
- No git SHA of the commit being tested
- No package version snapshot (which versions of gptel, nucleus, self-heal were active)
- No lockfile hash
- No API response metadata capture (model version, finish_reason, token counts)
- No formal probe specification — hypotheses are free-text, not structured

**Concrete suggestion:** Add `var/context/<id>-provenance.json` per experiment:
```json
{
  "experiment_id": "20260612T104532Z-a3f2",
  "git_sha": "a3f2c1...",
  "emacs_version": "30.1",
  "package_versions": {"gptel": "0.9.7", "nucleus": "1.2.0"},
  "active_modules": ["gptel-auto-workflow", "gptel-auto-experiment", ...],
  "backend": "DashScope/qwen3.6-plus",
  "model_revision": "main",
  "finish_reason": "stop",
  "token_counts": {"prompt": 4200, "completion": 850}
}
```

This is ~200 bytes per experiment. Near-zero storage cost, massive debuggability gain. The existing `var/context/*.sexp` sidecar already captures business rationale — extend it with a provenance sub-struct.

---

### Gap 7: No structure-preserving compression of knowledge representations (transferability: medium)

**What verbum does:** 2-Mirror Ternary Quantization uses the φ-predicted eigenvalue structure to separate sign and magnitude, achieving better reconstruction quality (recon_cos=0.970) with fewer bits (4.0) than standard Q4 (4.5 bits, recon_cos=0.95). The core insight: **you can compress without quality loss if you preserve the eigenvalue structure.**

**What OV5 lacks:** OV5's knowledge layer spans markdown (mementum), JSON (schema index), SEXP (context sidecars), OWL/SHACL (ontology), and TSV (experiment results). All are stored uncompressed. No attempt to:
- Quantize the ontology graph for faster retrieval
- Compress the experiment TSV while preserving rank-ordering of experiments
- Prune redundant knowledge while preserving retrieval accuracy

**Concrete suggestion:** Apply structure-preserving compression to the ontology graph:
- The ontology has ~200 classes and ~500 relationships. Factor the adjacency matrix and test whether a low-rank approximation preserves retrieval accuracy.
- If rank-8 approximation of the 200×200 adjacency matrix preserves >0.95 retrieval recall, use it as a fast cache layer.
- **Do not** attempt this on mementum markdown (human-readable is the point). Target: the machine-consumed JSON/OWL representations only.

---

## What OV5 is already ahead on (no gap)

| verbum strength | OV5 already matches or exceeds |
|---|---|
| VSM architecture (S5-S1) | Shared. OV5's VSM is operationalized with 10-phase monitoring |
| Mementum memory protocol | Shared. Same git-based persistence |
| Lambda notation | OV5 uses it as primary prompt format (59% compression) |
| Null testing | Absorbed. verbum-audit-methodology.md documents the transfer |
| Register-matching | Absorbed. `λ measure(claim)` in AGENTS.md identity genes |
| Held-out evaluation | Operational. Evolution experiments use held-out targets |
| Variance decomposition | Present in self-heal diagnostics (pre/post fixer verification) |

---

## Priority ordering

| Priority | Gap | Why this order | Cost to implement |
|---|---|---|---|
| P0 | **Gap 6** — Provenance surface | Near-zero cost, huge debuggability. Every future gap analysis benefits from having git SHA + package versions per experiment. | ~50 lines of Elisp |
| P0 | **Gap 1** — Pipeline statechart | Answers "where is the bottleneck?" without guessing. Empirically grounded in existing TSV data. | ~100 lines, pure data analysis |
| P1 | **Gap 2** — Per-gate score vectors | Prevents compensating errors going undetected. Natural extension of existing grading. | ~40 lines, extends existing grade fn |
| P1 | **Gap 4** — Kronecker factorization | Tells you whether to unify strategies or diversify. One matrix factorization answers a high-level architecture question. | ~60 lines, numpy via brepl |
| P2 | **Gap 3** — Parameter-reduction law | High upside if it exists, but low probability. Worth a single-cycle test. | ~30 lines, one analysis pass |
| P2 | **Gap 5** — Compute cycle mapping | Interesting but speculative. Could inform phase reordering if validated. | ~50 lines, requires phase-timing instrumentation first |
| P3 | **Gap 7** — Knowledge compression | Useful for scale, but premature. OV5's knowledge graph is <1MB. Compression becomes valuable at 10-100x current size. | ~100 lines + retrieval benchmark |

---

## References

- verbum: https://github.com/davidwuchn/verbum
- verbum-audit-methodology.md — null testing and register-matching already absorbed
- OUROBOROS-V5.md — OV5 architecture reference
- simmis-vs-ov5-gap-analysis.md — prior gap analysis (analogous structure)
- memgraphrag-gap-analysis.md — prior gap analysis (analogous structure)
