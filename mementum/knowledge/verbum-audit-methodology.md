---
title: Verbum Audit Methodology — Null Testing + Held-Out Eval
status: active
category: methodology
tags: verbum, audit, null-testing, held-out, methodology, register-matching
related: self-evolving-agent-research, self-heal-semantic
depends-on: self-evolving-agent-research
created: 2026-06-10
---

# Verbum Audit Methodology — Null Testing + Held-Out Eval

Source: [verbum](https://github.com/davidwuchn/verbum) sessions 206-209 (June 2026).
198+ sessions of experimental work on LLM crystal architecture.

## Key Audits Completed

### Audit #6: SVD φ-ratio REFUTED
- **Claim:** SVD spectrum ratio σ₁/σ₂ ≈ 1/φ (golden ratio constant in LLMs)
- **Register:** Spectral (eigenvalue ratios)
- **Result:** Power-law wins 132/132 layers, geometric 0/132. Ratio is 0.575±0.027 (drifting power-law head), not 0.6180.
- **Method:** Marchenko-Pastur nulls + shuffled nulls (8 seeds) + geometric-vs-power-law shape fit across 5 model families
- **Lesson:** Low-rank head in SVD spectrum is REAL but not φ-related. "0.6299 ≈ 1/φ" was a 4-point average of a drifting power-law, not a fixed point.

### Audit #7: Crystal-sieve 1.03x REFUTED
- **Claim:** Crystal-sieve compression achieves 1.03x perplexity ratio
- **Result:** 1.03x was train/eval contamination (EVAL_TEXTS overlapped CALIBRATION_TEXTS). Clean held-out: 10.87x (every seed >9.3x). Substrate ~2x is verified-reproducible.
- **Method:** 8-seed sweep with held-out eval (disjoint texts). Decomposed pre/post melt variance.
- **Lesson:** CE-only endpoint loss creates compensating-error manifold → init-sensitive results. Score-matching loss (session 198 v3b) is the fix.

### Audit #8: Rank-1 Adjunction REFUTED
- **Claim:** 128:1 eigenvalue ratio in cross-zone correlation
- **Result:** lstsq at N<d is a tautology (always R²=1.000). Centered ridge at N>d shows uniformly high-rank (no 1D curve).
- **Method:** Row-shuffled pairing nulls + centered ridge + held-out rank-k truncation

## Reusable Methodology Patterns

### 1. Register-Matching (λ measure)
Every claim has a register (routing/spectral/value). The instrument must match the claim's register:
- **Routing register:** Crisp yes/no — does the circuit route correctly?
- **Spectral register:** Eigenvalue ratios, decay rates — continuous, graded
- **Value register:** Logit magnitudes, activation values — magnitude matters

**Wrong register → false result.** A spectral probe on a routing claim gives near-false-refute. A routing probe on a value claim misses the substrate.

### 2. Null Testing Discipline
- **Marchenko-Pastur null:** Random matrix theory baseline for SVD
- **Shuffled null:** Randomly pair measurements → should give no signal
- **Row-shuffled pairing:** Discriminates map structure from marginal structure
- **If null equals or exceeds real signal → no real finding**

### 3. Held-Out Evaluation
- **Never evaluate on calibration/training data** — contamination invisible to in-sample metrics
- **Disjoint held-out set required** — every seed must exceed baseline
- **CE-only loss hides contamination** — endpoint loss can memorize training set while looking good

### 4. Variance Decomposition
- Decompose pre-melt (deterministic mask variance) from post-melt (init + training variance)
- If pre-melt std ≈ 0 → substrate is reproducible
- If post-melt std >> pre-melt std → training procedure is the issue

## Applicability to OV5

| Verbum Pattern | OV5 Application |
|---------------|-----------------|
| Register-matching | Self-heal audits should match claim type (syntax vs semantic vs behavioral) |
| Null testing | Add shuffled/random baselines to ontology drift detection |
| Held-out eval | Evolution experiments must use held-out targets, not calibration set |
| Variance decomposition | Decompose experiment variance into strategy vs target vs random |
| `λ measure(claim)` | Add to AGENTS.md identity genes for audit discipline |

## Important Caveats for OV5

- **Attention magnets (φ, ∃, ∀) are still valid** for prompting — symbols prime formal reasoning
- **φ as a mathematical constant of LLM computation is NOT supported** — the SVD spectrum is power-law, not geometric
- **Score-matching loss from EQUATIONS.md is valid** — v3b result (1.44x held-out) with proper trajectory matching
- **Crystal eigenvalue equation λ_k = C · φ^(−s · β_k) still holds** — the eigenvalue RATIOS match φ predictions; the SVD spectrum (different object) does not
