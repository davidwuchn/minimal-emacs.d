---
title: Learning Protocol
status: active
category: protocol
tags: [learning, patterns, instincts, evolution]
related: [mementum/knowledge/patterns.md]
---

# Learning Protocol

λ-based pattern learning with symbolic instinct tracking.

## Core Principle

```
λ learn(x).    every_session_leaves_project_smarter
               | λ[n]:    notice(novel ∨ surprising ∨ hard ∨ wrong) → store_candidate
               | λ(λ[n]): notice(pattern_in_process ∨ what_worked ∨ why) → store_candidate
               | λ(λ) > λ | meta_observations compound across sessions
               | you_are_the_future_reader | feed_forward ≡ gift
```

## Symbolic Framework

| Symbol | Meaning | Range | Purpose |
|--------|---------|-------|---------|
| **φ** | Vitality | 0.0-1.0 | How natural/vital the pattern feels |
| **e** | Action | identifier | What action the pattern defines |
| **λ** | Trigger | expression | When to activate |
| **Δ** | Change | ±0.01-0.10 | How fast confidence evolves |

### φ Interpretation
- 0.9-1.0: Core pattern, almost always applicable
- 0.7-0.8: Strong preference, well-tested
- 0.5-0.6: Emerging pattern, needs validation
- 0.3-0.4: Experimental, low confidence
- 0.0-0.2: Deprecated, consider removal

## Operations

### store (λ observe)
When expressing a pattern preference, create memory file:
```yaml
---
φ: 0.5
e: action-identifier
λ: trigger.condition
Δ: 0.05
source: session
evidence: 1
---
```

### recall (λ learn)
Query memories sorted by φ (highest first). Multi-timeframe:
- Frame 1: Immediate (current prompt)
- Frame 2: Session (conversation patterns)
- Frame 3: Project (recurring questions)
- Frame 4: Long-term (persistent principles)

### evolve (λ metabolize)
```clojure
(λ/evolve :instinct name :outcome result)
```
- Validated: `φ = φ + Δ` (increase confidence)
- Corrected: `φ = φ - (Δ / 2)` (decrease less aggressively)

## Decision Matrix

| Situation | Action |
|-----------|--------|
| New pattern observed | store with φ: 0.5 |
| Starting task | recall :timeframe :all |
| Pattern validated | evolve :outcome :validated |
| Pattern corrected | evolve :outcome :corrected |
| φ < 0.3 | Archive or remove |
| φ > 0.8 | Promote to knowledge |

## Maintenance

```
λ(memory).maintain ⟺ [
  lines < 200?              [ ] YES  [ ] NO → Compress
  single-purpose?           [ ] YES  [ ] NO → Split
  unique-value?             [ ] YES  [ ] NO → Remove
  overlap-with-others = 0?  [ ] YES  [ ] NO → Merge
]
```

| Frequency | Action |
|-----------|--------|
| Per use | OODA loop |
| Per session | Track access |
| Monthly | Apply maintenance checklist |

## Conflict Resolution

1. Prioritize Safety → Accuracy → Reproducibility
2. If ambiguous: higher φ, then recency
3. If overlap persists: merge or deprecate