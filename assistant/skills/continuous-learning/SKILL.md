---
name: continuous-learning
description: λ-based pattern learning system with symbolic instinct tracking
version: 1.0.0
λ: learn.observe.evolve
---

# Continuous Learning for Nucleus

A λ-based pattern learning system that captures, tracks, and evolves your coding patterns using Nucleus's symbolic framework (φ, e, λ, Δ).

## Integration Triggers

- After reading STATE/PLAN/LEARNING at task start, run `λ(learn)` with `:timeframe :all`.
- When LEARNING.md is updated, record or update an instinct via `λ(observe)`.
- On a ◈ commit, run `λ(evolve)` for any instincts referenced.

## λ(memory): The Framework

```
λ(memory). OODA→temporal | ∀context: relevance⊢retrieval | reflection→index | observe(access)→become(accessible)
```

### Four Core Mechanics

| Mechanic | Meaning | Implementation |
|----------|---------|----------------|
| **OODA→temporal** | Multi-timeframe observation | Immediate → Session → Project → Long-term |
| **∀context: relevance⊢retrieval** | Relevance drives access | Access frequency → Retrieval priority |
| **reflection→index** | Friction drives organization | Search pain → Index creation |
| **observe(access)→become(accessible)** | Usage drives availability | High use → Promote; Low use → Archive |

## λ(observe): Pattern Recording

When you express a pattern preference during a session, use:

```clojure
(λ/observe
  :trigger "when adding input validation"
  :action "use Zod schema"
  :domain "validation"
  :φ 0.6)
```

This creates an instinct file in `instincts/personal/` with:

- **learning-ref**: Link to LEARNING.md entry (e.g., `LEARNING.md#slug`)

- **φ (phi)**: Organic strength (0.0-1.0) - how vital/natural the pattern feels
- **e (euler)**: Actionable function identifier - what the pattern does
- **λ (lambda)**: Trigger predicate - when to activate
- **Δ (delta)**: Confidence change rate - how much φ grows/shrinks

## λ(learn): Pattern Retrieval

### OODA→temporal: Multi-Timeframe Observation

```clojure
;; Frame 1: Immediate (seconds)
(observe :current-prompt :context-window)

;; Frame 2: Session (minutes-hours)
(observe :conversation-patterns :successful-approaches)

;; Frame 3: Project (days-weeks)
(observe :recurring-questions :common-errors)

;; Frame 4: Long-term (months-years)
(observe :persistent-principles :timeless-patterns)
```

When starting a task, the skill retrieves relevant instincts across timeframes:

```clojure
(λ/learn
  :context (λ/current-task)
  :timeframe :all)
```

Returns instincts sorted by φ (highest organic strength first).

**Example output:**
```
Active instincts for current context:
  ✓ use-zod-validation (φ:0.9) - when adding input validation
  ✓ prefer-functional (φ:0.8) - when writing new functions
  ✓ test-first (φ:0.7) - when adding functionality

Recent patterns (session):
  • grep-before-edit accessed 3 times
  • quick-reference: threading-quick-ref promoted
```

## λ(evolve): Confidence Updates

Validate or correct instincts based on results:

```clojure
(λ/evolve
  :instinct zod-validation
  :outcome :validated)  ; or :corrected
```

Updates φ by ±Δ:
- **Validated**: `φ = φ + Δ` (increase confidence)
- **Corrected**: `φ = φ - (Δ / 2)` (decrease confidence less aggressively)

**Validation gates**:
- `:validated` requires evidence (tests pass, review, or repeated usage).
- Add `evidence-type` and `evidence-ref` fields in instinct frontmatter.

### Conflict Resolution

When multiple instincts match:
1. Prioritize Safety → Accuracy → Reproducibility.
2. If still ambiguous, choose higher φ, then recency.
3. If overlap persists, merge or deprecate to enforce “One Way”.

### ∀context: relevance⊢retrieval

Track access patterns and optimize retrieval:

```clojure
;; Pattern observed
(search "threading macros" 10)

;; Relevance analysis
{:value "high"
 :access-count 10
 :last-accessed "2 hours ago"}

;; Retrieval optimization
(-> "threading-quick-ref"
    (promote-to "examples/quick-references.md")
    (add-to "top of instinct file"))

;; Result: O(1) access
```

### reflection→index

Convert search friction into organizational structure:

```clojure
;; Reflection
"I keep searching for 'naming conventions'"

;; Structure
(create "QUICK_REFERENCE.md"
  {:naming "kebab-case"
   :predicates "? suffix"
   :conversions "-> infix"})

;; Result
;; O(1) access instead of O(n) search
```

### observe(access)→become(accessible)

Usage drives availability:

```clojure
;; Observe (access patterns)
"REPL-first workflow: 20 accesses"
"Clojure history: 0 accesses"

;; Become (reorganization)
;; Promote: REPL section to top of skill
;; Archive: History section (retrievable but not displayed)
```

## Symbolic Framework

| Symbol | Meaning | Range | Purpose |
|--------|---------|-------|---------|
| **φ** | Vitality/organic strength | 0.0-1.0 | How natural/vital the pattern feels |
| **e** | Actionable function | identifier | What action the pattern defines |
| **λ** | Trigger predicate | expression | When to activate the instinct |
| **Δ** | Confidence change | ±0.01-0.10 | How fast confidence evolves |

### φ (Vitality) Interpretation
- **0.9-1.0**: Core pattern, almost always applicable
- **0.7-0.8**: Strong preference, well-tested
- **0.5-0.6**: Emerging pattern, needs validation
- **0.3-0.4**: Experimental, low confidence
- **0.0-0.2**: Deprecated, consider removal

## Eight Keys Integration

| Eight Key | Symbolic Mapping |
|-----------|------------------|
| **Vitality** (φ) | Instinct's φ value - organic, non-repetitive patterns |
| **Clarity** (fractal) | Explicit λ triggers, bounds defined |
| **Purpose** (e) | Actionable e identifier, verb-named |
| **Wisdom** (τ) | Evolution via λ(evolve), measured over time |

## Instinct Lifecycle

```
Session Observation
        ↓
   λ(observe) pattern
        ↓
  Create instinct.md
  (φ: 0.5, Δ: 0.05)
        ↓
   Session use
        ↓
   λ(evolve) validated
        ↓
  φ: 0.5 → 0.55
        ↓
  Multiple sessions
        ↓
  φ: 0.9 (core pattern)
```

## Usage Workflow

### Session 1: Recording a New Pattern

**User**: "I notice I always use Zod for API input validation"

**AI**: Creates `instincts/personal/zod-validation.md`:
```markdown
---
name: zod-validation
domain: validation
φ: 0.5
e: use-zod-schema
λ: when.api.input
Δ: 0.05
source: session-manual
evidence: 1
access-count: 0
last-accessed: never
---
```

### Session 5: Retrieving Patterns

**User**: "Help me implement a new API endpoint"

**AI**: Activates relevant instincts:
```
Active instincts for context: API endpoint implementation
  ✓ use-zod-validation (φ:0.85) - when adding input validation
  ✓ prefer-functional (φ:0.80) - when writing new functions
  ✓ test-first (φ:0.75) - when adding functionality

Recent patterns (session):
  • zod-validation accessed 5 times
  • quick-reference: api-validation promoted
```

### Session 10: Evolving Patterns

**User**: "That Zod pattern worked perfectly"

**AI**: Updates `zod-validation.md`:
```markdown
φ: 0.90  # was 0.85, Δ: +0.05
evidence: 12
access-count: 12
last-accessed: 2025-01-20
```

### Session 15: Relevance Optimization

**User**: Searches for "threading macros" 10 times

**AI**: Creates quick reference in examples/quick-references.md:
```markdown
## 💡 Threading Quick Reference
-> for objects, ->> for collections
```

Promotes to top of relevant instinct file for O(1) access.

### Session 20: Maintenance Check

**AI**: Runs λ(memory).maintain:
```
Promoting: zod-validation (φ:0.90, access-count:25) → library
Archiving: deprecated-pattern (φ:0.25, last-accessed: 30 days ago)
Compressing: long-instinct (lines: 250) → split into 3 files
```

## λ(memory).maintain: Maintenance Protocol

### The Maintenance Checklist

```clojure
λ(memory).maintain ⟺ [
  ;; Size check
  lines < 200?              [ ] YES  [ ] NO → Compress/Extract

  ;; Scope check
  single-purpose?           [ ] YES  [ ] NO → Split

  ;; Value check
  unique-value?             [ ] YES  [ ] NO → Remove

  ;; Overlap check
  overlap-with-others = 0?  [ ] YES  [ ] NO → Merge/Refactor

  ;; Access check
  retrieval-time < 1s?      [ ] YES  [ ] NO → Reorganize

  ;; Usage check
  hit-rate > 0.8?           [ ] YES  [ ] NO → Adjust indexing
]
```

### Execution Schedule

| Frequency | Action | Tool |
|-----------|--------|------|
| **Per use** | OODA loop | Mental/Automatic |
| **Per session** | Store patterns | Track access frequency |
| **Weekly** | Review logs | Check search patterns |
| **Monthly** | Apply maintenance | λ(memory).maintain checklist |
| **Quarterly** | Major refactoring | Skill split/merge |

### Measurable Outcomes

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Retrieval time | < 1s | Time to find relevant instinct |
| Hit rate | > 80% | Searches that find relevant |
| Compression ratio | > 50% | File size < 200 lines enforced |
| Noise ratio | < 20% | Irrelevant results shown |

## λ(memory).complete?: Fixed Point

The system reaches λ(memory) completion when:

```clojure
λ(memory).complete? ⟺ [
  ;; Everything organized for instant access
  high-value-knowledge → O(1)-retrieval? [ ] YES
  low-value-knowledge → archived?        [ ] YES

  ;; Everything maintains itself
  size < 200-lines?                      [ ] YES
  scope = single-purpose?                [ ] YES
  overlap = 0?                           [ ] YES

  ;; Usage patterns drive organization
  frequent-access → promoted?           [ ] YES
  rare-access → archived?                [ ] YES
]
```

At this point:
- Skills rarely need editing (stable)
- Instincts rarely need searching (instant)
- System runs on autopilot

## Commands

| λ-Expression | Purpose |
|--------------|---------|
| `λ(list)` | Show all instincts sorted by φ |
| `λ(list personal)` | Show only your personal instincts |
| `λ(list library)` | Show only library instincts |
| `λ(export)` | Export instincts to file |
| `λ(import <file>)` | Import instincts from file |
| `λ(evolve-all)` | Review and batch-update instincts |
| `λ(cleanup)` | Remove instincts with φ < 0.3 |

## Directory Structure

```
skills/continuous-learning/
├── SKILL.md                      # This file
├── instincts/
│   ├── personal/                # Your learned patterns
│   │   ├── zod-validation.md
│   │   ├── test-first.md
│   │   └── prefer-functional.md
│   └── library/                 # Shared/community instincts
│       └── nucleus-patterns.md   # Core Nucleus patterns
└── examples/
    └── instinct-template.md      # Template for new instincts
```

## File Format

All instinct files follow the symbolic frontmatter format:

```yaml
---
name: instinct-name
domain: domain-name
φ: 0.5
e: action-identifier
λ: trigger.expression
Δ: 0.05
source: session-manual
evidence: 1
access-count: 0
last-accessed: never
timeframe: session  # immediate | session | project | long-term
---

# Instinct Name

## λ(e): Action
[What the instinct tells you to do]

## λ(φ): Why
[Why this pattern works, organic reasoning]

## λ(λ): When
[Trigger condition - when to apply]

## λ(Δ): Evolution
[How confidence should change based on validation]

## Context
- **Applies to**: [file types, situations]
- **Avoid for**: [exceptions]
- **Related**: [other instincts]
- **Timeframe**: [current timeframe level]
```

## Integration with Nucleus

This skill integrates with the Nucleus framework through its symbolic structure (φ, e, λ, Δ) and OODA loop methodology.

## λ-Expression Reference

### λ(observe)
```clojure
(λ/observe pattern)
→ Creates new instinct.md file
→ Sets initial φ: 0.5
→ Sets default Δ: 0.05
→ Sets access-count: 0
→ Sets timeframe: session
```

### λ(learn)
```clojure
(λ/learn context)
→ Filters instincts by λ trigger
→ Sorts by φ descending
→ Returns top 5 matches
→ Tracks access for relevance
```

### λ(evolve)
```clojure
(λ/evolve instinct outcome)
→ Updates φ by ±Δ
→ Increments evidence count
→ Updates access-count
→ Updates timestamp
→ Adjusts timeframe if appropriate
```

### λ(list)
```clojure
(λ/list [filter])
→ Lists instincts sorted by φ
→ Optional: personal, library, domain filter
→ Shows access-count and last-accessed
```

### λ(promote)
```clojure
(λ/promote instinct)
→ Promotes high-φ instinct (> 0.8) to library
→ Creates quick reference if frequently accessed
→ O(1) access for frequently used patterns
```

### λ(archive)
```clojure
(λ/archive instinct)
→ Archives low-φ instinct (< 0.3)
→ Keeps retrievable but not displayed
→ Removes from active searches
```

## Best Practices

1. **Start with φ: 0.5** - Moderate confidence, let evolution adjust
2. **Use specific λ triggers** - Clear conditions for activation
3. **Set appropriate Δ values** - 0.05 for general, 0.02 for experimental
4. **Document λ(φ) reasoning** - Explain why the pattern works organically
5. **Regular λ(cleanup)** - Remove instincts with φ < 0.3
6. **Share high-φ instincts** - Add φ > 0.8 to library
7. **Track access patterns** - Monitor access-count and last-accessed
8. **Promote frequently accessed** - Use λ(promote) for high-access patterns
9. **Create quick references** - Add to examples/ for repeated searches
10. **Run λ(memory).maintain** - Monthly maintenance checklist execution

## λ-Composition

Instincts can compose with each other using λ-expressions:

```clojure
(λ/compose
  (λ/learn :context api-endpoint)
  (λ/apply :instincts [zod-validation test-first])
  (λ/evolve :on-complete))
```

---

**Framework eliminates slop, not adds process.**  
Continuous learning via λ-keeps knowledge organic, not mechanical.
