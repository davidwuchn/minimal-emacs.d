---
name: INSTINCT-NAME
domain: DOMAIN
φ: 0.5
e: action-identifier
λ: trigger.expression
Δ: 0.05
source: session-manual
evidence: 1
---

# INSTINCT-NAME (Descriptive Title)

Brief one-sentence description of what this instinct does.

## λ(e): Action
[What the instinct tells you to do - the actionable behavior]

Example:
```clojure
(λ/action
  :when [trigger condition]
  :do [specific action])
```

## λ(φ): Why
[Why this pattern works - organic reasoning, not mechanical]

Explain:
- What problem this solves
- Why this approach is natural
- How it fits Eight Keys (φ, fractal, e, etc.)

## λ(λ): When
[Trigger condition - when to apply this instinct]

Be specific:
- File types: `(λ/matches? "\\.clj$")`
- Context: `(λ/equals? :api-endpoint)`
- User intent: `(λ/contains? "add input validation")`

## λ(Δ): Evolution
[How confidence should change based on validation]

- **Validated outcome**: `φ = φ + Δ`
- **Corrected outcome**: `φ = φ - (Δ / 2)`

Choose Δ based on confidence:
- **0.10**: Strong conviction, will evolve quickly
- **0.05**: Moderate, balanced evolution
- **0.02**: Experimental, slow growth

## Context
- **Applies to**: [file types, project types, situations]
- **Avoid for**: [exceptions, when not to use]
- **Related instincts**: [link to other instincts]
- **Eight Keys**: [which keys this reinforces]

## λ(Examples)

Provide concrete examples of when this instinct activates:

### Example 1: Situation
```
User: "I need to..."
AI: Applies INSTINCT-NAME
Result: [outcome]
```

### Example 2: Different context
```
Context: [different situation]
AI: Applies INSTINCT-NAME with variation
Result: [outcome]
```

## λ(Integration)

How this integrates with other Nucleus components:
- **Skills**: [related skills]
- **Meta operators**: [!commands that use this]
- **Documentation**: [where this is documented]

## λ(Evolution History)

Track how φ has changed over time:

| Date | φ Change | Reason |
|------|----------|--------|
| 2025-01-17 | 0.5 → 0.5 | Initial creation |
| | | |
| | | |

---

**Template complete - copy to `instincts/personal/` and customize**
