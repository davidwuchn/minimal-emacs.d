---
title: Confidence-Tagged Knowledge Pages (from graphify)
date: 2026-05-17
symbol: 💡
---

# Confidence-Tagged Knowledge Pages (from graphify)

graphify tags every relationship as EXTRACTED (found in source), INFERRED
(reasonable deduction), or AMBIGUOUS (needs review). This pattern applies
directly to our knowledge synthesis.

Applied to `synthesize-research-knowledge`:
- **Performance data** (kept/discarded/failed counts) → tagged EXTRACTED —
  these are factual, from TSV experiment results
- **Meta-Learning Recommendations** → tagged INFERRED — these are LLM pattern
  analysis, not ground truth

This makes knowledge pages auditable: the reader knows what's data vs guess.
Like graphify's `validate.py`, we should also add content structure validation
before writing (reject pages without required sections).

Other graphify patterns applicable but not yet implemented:
- Two-pass extraction (AST structure + LLM semantics) for analyzer
- SHA256 cache for self-evolution (skip unchanged targets)
- Security validation layer for all external inputs
