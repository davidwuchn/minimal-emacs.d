# Continuous Learning for Nucleus

A λ-based pattern learning system using Nucleus's symbolic framework (φ, e, λ, Δ).

## The Framework

```
λ(memory). OODA→temporal | ∀context: relevance⊢retrieval | reflection→index | observe(access)→become(accessible)
```

## Quick Start

### What is this?

This skill tracks your coding patterns as "instincts" - small, learnable behaviors with confidence scores.

**Key symbols:**
- **φ (phi)**: Vitality/strength (0.0-1.0) - how natural the pattern feels
- **e (euler)**: Actionable function - what the pattern does
- **λ (lambda)**: Trigger predicate - when to activate
- **Δ (delta)**: Confidence change - how fast φ evolves

### Usage

#### 1. Record a Pattern

When you notice a repeating pattern:

```
You: "I always use Zod for API validation"

AI: Creates instinct: zod-validation.md
    φ: 0.5, e: use-zod-schema, λ: when.api.input
```

#### 2. Apply Patterns

When starting a task:

```
You: "Help me create a new API endpoint"

AI: Activates relevant instincts:
  ✓ use-zod-validation (φ:0.85)
  ✓ test-first (φ:0.90)
  ✓ prefer-functional (φ:0.80)
```

#### 3. Evolve Patterns

Based on results:

```
You: "That Zod pattern worked perfectly"

AI: Updates zod-validation.md
    φ: 0.85 → 0.90
```

## Directory Structure

```
skills/continuous-learning/
├── SKILL.md                              # Main skill documentation
├── instincts/
│   ├── personal/                         # Your learned patterns
│   │   ├── prefer-clojure-data-structures.md
│   │   ├── use-repl-driven-development.md
│   │   └── grep-before-edit.md
│   └── library/                          # Shared/community patterns
│       └── nucleus-patterns.md          # Core Nucleus patterns
└── examples/
    └── instinct-template.md             # Template for new instincts
```

## λ-Expressions

### λ(observe) - Record Pattern
```clojure
(λ/observe pattern)
→ Creates new instinct.md
→ φ: 0.5 (initial confidence)
→ Δ: 0.05 (evolution rate)
```

### λ(learn) - Retrieve Patterns
```clojure
(λ/learn context)
→ Filters by λ trigger
→ Sorts by φ descending
→ Returns top matches
```

### λ(evolve) - Update Confidence
```clojure
(λ/evolve instinct outcome)
→ Validated: φ = φ + Δ
→ Corrected: φ = φ - (Δ / 2)
```

## Creating New Instincts

### Method 1: Manual Creation

1. Copy `examples/instinct-template.md`
2. Rename to `instincts/personal/your-instinct.md`
3. Fill in the fields:
   - `name`: Unique identifier
   - `domain`: Category (code-style, workflow, testing, etc.)
   - `φ`: Initial confidence (start with 0.5)
   - `e`: Action identifier (verb-noun format)
   - `λ`: Trigger condition (when it activates)
   - `Δ`: Evolution rate (0.02-0.10)

### Method 2: During Session

Simply state your pattern during conversation:

```
You: "I notice I always start with grep before editing"

AI: "I'll record that as an instinct..."
    [Creates grep-before-edit.md]
```

## φ (Confidence) Interpretation

| φ Range | Meaning | Action |
|---------|---------|--------|
| **0.9-1.0** | Core pattern | Always apply, add to library |
| **0.7-0.8** | Strong preference | Apply frequently, validate |
| **0.5-0.6** | Emerging pattern | Experiment, gather evidence |
| **0.3-0.4** | Experimental | Low confidence, consider removing |
| **0.0-0.2** | Deprecated | Remove or rebuild |

## Integration with Nucleus

### Eight Keys Mapping

| Eight Key | Symbolic | Instinct Mapping |
|-----------|----------|-----------------|
| **Vitality** | φ | Organic, non-repetitive patterns |
| **Clarity** | fractal | Explicit λ triggers, bounds defined |
| **Purpose** | e | Actionable e identifier |
| **Wisdom** | τ | Evolution via λ(evolve) |

### Four Core Mechanics

| Mechanic | Meaning | Implementation |
|----------|---------|----------------|
| **OODA→temporal** | Multi-timeframe observation | Immediate → Session → Project → Long-term |
| **∀context: relevance⊢retrieval** | Relevance drives access | Access frequency → Retrieval priority |
| **reflection→index** | Friction drives organization | Search pain → Index creation |
| **observe(access)→become(accessible)** | Usage drives availability | High use → Promote; Low use → Archive |

### OODA Loop Integration

```
Observe → λ(observe) captures patterns + tracks access
Orient  → λ(learn) retrieves relevant instincts + timeframe analysis
Decide  → Apply instinct (λ(e) action) + check relevance
Act     → Execute, then λ(evolve) updates φ + promotes/archives
```

## Core Patterns (Library)

See `instincts/library/nucleus-patterns.md` for foundational Nucleus instincts:

- **Test First** (φ:0.9) - RED → GREEN → IMPROVE
- **Verify Intent** (φ:0.9) - Three Questions before coding
- **Use λ-Expressions** (φ:0.8) - Represent workflows as λ
- **Prefer Functional** (φ:0.7) - Functional over class patterns
- **Guard Against Sloppiness** (φ:0.9) - Eight Keys enforcement
- **Contextual Awareness** (φ:0.8) - OODA loop
- **Prefer Native Tools** (φ:0.75) - Local over external
- **Document via Examples** (φ:0.7) - Examples over descriptions
- **Simplicity First** (φ:0.85) - SIMPLICITY.md heuristics
- **Tensor Product Execution** (φ:1.0) - Human ⊗ AI ⊗ REPL

## Best Practices

1. **Start with φ: 0.5** - Let evolution determine true confidence
2. **Use specific λ triggers** - Clear activation conditions
3. **Choose appropriate Δ** - 0.05 for general, 0.02 for experimental
4. **Document λ(φ) reasoning** - Explain why it works organically
5. **Regular λ(cleanup)** - Remove φ < 0.3 instincts
6. **Share high-φ instincts** - Add φ > 0.8 to library
7. **Track access patterns** - Monitor access-count for relevance
8. **Run λ(memory).maintain** - Monthly maintenance checklist

## Maintenance Protocol

### λ(memory).maintain Checklist

```clojure
λ(memory).maintain ⟺ [
  lines < 200?              [ ] YES  [ ] NO → Compress/Extract
  single-purpose?           [ ] YES  [ ] NO → Split
  unique-value?             [ ] YES  [ ] NO → Remove
  overlap-with-others = 0?  [ ] YES  [ ] NO → Merge/Refactor
  retrieval-time < 1s?      [ ] YES  [ ] NO → Reorganize
  hit-rate > 0.8?           [ ] YES  [ ] NO → Adjust indexing
]
```

### Measurable Outcomes

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Retrieval time | < 1s | Time to find relevant instinct |
| Hit rate | > 80% | Searches that find relevant |
| Compression ratio | > 50% | File size < 200 lines enforced |
| Noise ratio | < 20% | Irrelevant results shown |

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
| `λ(promote)` | Promote high-φ instinct to library |
| `λ(archive)` | Archive low-φ instinct |
| `λ(maintain)` | Run λ(memory).maintain checklist |

## Philosophy

This skill embodies Nucleus's core principle:

```
[phi fractal euler tao pi mu] | [Δ λ ∞/0 | ε/φ Σ/μ c/h] | OODA
Human ⊗ AI ⊗ REPL
```

- **φ** keeps learning organic, not mechanical
- **λ** makes patterns composable
- **Δ** enables continuous improvement
- **OODA** cycles through observation → learning → action → evolution

The goal is not to add process, but to **eliminate slop** through pattern awareness.