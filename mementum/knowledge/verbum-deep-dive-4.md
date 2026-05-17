---
title: Verbum Deep Dive #4 — Lambda Kernel Probes (400 probes, 15 axes)
date: 2026-05-17
symbol: 💡
---

# Verbum Deep Dive #4 — Lambda Kernel Probes

verbum's `lambda_kernel_probes.py` contains ~400 probes across 15 λ-calculus
operation axes in 4 tiers. This is a CAPABILITY TAXONOMY for LLM behavior.

## Operation Axes → Experiment Categories

| Axis | λ Meaning | Our Experiment Category | Example |
|------|-----------|------------------------|---------|
| K | Select/discard | nil-safety, guards | "add nil guard to X" |
| I | Identity/reference | passthrough, binding | "pass value unchanged" |
| B | Compose/chain | DRY, helper extraction | "extract helper from X" |
| C | Flip/reorder | refactor, reorder | "reorder args in X" |
| M | Match/retrieve | pattern application | "apply pattern from Y to X" |
| W | Duplicate | dedup, unify | "merge duplicate logic" |
| T | Type-raise | type validation | "add type check to X" |
| Φ | Fork/parallel | multi-property | "add guard + test to X" |
| D | Deep compose | multi-step refactor | "extract → validate → apply" |

## Key Design Principles

### Minimal Pairs (already implemented)
Each probe pair differs in EXACTLY one operation.
Our `detect-minimal-pairs` does this for experiments.

### Density (20-30 probes per axis)
verbum uses 20-30 probes per axis for statistical significance.
Our experiments need >5 per category before drawing conclusions.
Our `evolution-backend-stats` requires >5 already — apply same threshold to axis stats.

### Cross-Operation Contrast
Probes designed to be AMBIGUOUS between two operations.
Our minimal pair detection could identify K_vs_I pairs:
"add nil guard" (K) vs "pass unchanged" (I) on same function.

### Tiered Discovery
Tier 1 (confirmed) → Tier 2 (predicted) → Tier 3 (structural) → Tier 4 (meta)
Our strategy evolution could follow the same progression:
- Tier 1: nil-safety, type checks, DRY (confirmed useful)
- Tier 2: multi-property changes, deep refactors (experimental)
- Tier 3: scope/architecture changes (structural)
- Tier 4: self-modification, recursion patterns (meta)

## What We Should Apply

1. **Axis-tag experiments**: Add `:axis` tag to experiments based on hypothesis
   content. This enables per-axis performance analysis like verbum.

2. **Axis density threshold**: Require >5 experiments per axis before making
   conclusions (matching verbum's 20-30 probe density standard).

3. **Cross-axis contrast detection**: Extend minimal pair detection to identify
   experiments that test CONTRASTING operations, not just similar ones.
