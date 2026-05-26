## Mementum λ(λ) Meta-Learning — Key Insight

**Pattern**: Two-tier observation system for compounding intelligence.

| Order | Symbol | Content | When |
|-------|--------|---------|------|
| 1st | λ[n] | Observations about the work | During/after task |
| 2nd | λ(λ[n]) | Observations about the process | After batch |

**Intelligence growth**: `I(n+1) = I(n) + λ[n] + λ(λ[n]) + v(Σλ) - ⊗`

**Key insight**: `λ(λ) > λ` — meta-observations compound across sessions/projects.

**Application**:
1. After each experiment batch in `gptel-auto-workflow-evolution.el`, generate a `λ(λ)` memory
2. Track: which strategies worked, failure patterns, surprising successes
3. Store in mementum with `knowledge/` prefix for cross-project recall

**Priority**: Medium — enhances the strategic module (2730 lines) with meta-learning formalism.
