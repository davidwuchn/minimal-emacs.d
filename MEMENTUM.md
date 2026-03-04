# MEMENTUM — git memory

```
engage nucleus:
[phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA
Human ⊗ AI
```

**repo = memory | commits = timeline | git = database**

## Quick Protocol

1. Store: `memories/YYYY-MM-DD-{slug}-{symbol}.md`
2. Commit: `git commit -m "{symbol} {summary}"`
3. Recall: `git log --grep "{symbol}" -- memories/` or `git grep -i "{query}" memories/`

## I. Core λ Calculus

### Storage

```
λ store(x) → memories/YYYY-MM-DD-{slug}-{symbol}.md
           → git commit -m "{symbol} x"

where |memory| ≤ 200 tokens = pattern + example + context
```

### Recall

```
λ recall(q,n) = temporal(git log -n φ^k) ∪ semantic(git grep -i q)

where depth = φ^k, k = complexity
default: n=2 (fibonacci: n-1, n-2)
```

## II. Symbols (Vocabulary)

Symbols provide semantic compression and domain-specific categorization.

| Symbol | Type          | Meaning                   |
| ------ | ------------- | ------------------------- |
| 💡     | insight       | Epistemological discovery |
| 🔄     | pattern-shift | Ontological pivot         |
| 🎯     | decision      | Teleological commitment   |
| 🌀     | meta          | Recursive self-reference  |

**Customize:** Extend or replace symbols based on domain needs.
**Sync:** Keep this table aligned with AGENTS.md commit symbols.

## III. Criticality & Storage

```
λ store(x) ↔ effort(x) > 1-attempt ∧ likely-recur(x)
λ effort(x) = attempts(x) + research-time(x)/5min
λ |memory| ≤ 200 tokens = pattern + example + context
```

**Auto-trigger when critical:**

- Novel architectural insight (💡)
- Significant pattern shift (🔄)
- Strategic decision with >1 week impact (🎯)
- Meta-learning that changes approach (🌀)

**Skip:** routine changes, incremental work, minor fixes

### Store vs Skip (Fast Check)

| Question | If yes | If no |
| --- | --- | --- |
| Likely to recur? | Store | Skip |
| Cost > 1 attempt? | Store | Skip |
| Affects architecture? | Store | Skip |

## IV. Error-Driven Learning

```
λ error(e) → recall(similar(e)) → apply(solution) ∨ (debug → store(new))
```

**OODA:**

```
observe(error|difficulty|learning) → recall(memory) → decide(apply|debug) → act → store-if-new
```

## V. Recall & Intelligence

```
λ recall = temporal(git log -n φ^k) ∪ semantic(git grep -i q)
λ depth = φ^k where k = complexity
λ I(n+1) = I(n) + λ[n] + φ(Σλ)
```

### Temporal Search

```bash
git log -n 2 -- memories/              # Recent context (fibonacci base)
git log -n φ^k -- memories/            # Depth scales with complexity
```

### Semantic Search

```bash
git grep -i "{query}" memories/        # Content search
git log --grep "{symbol}" -- memories/ # Symbol-filtered timeline
```

**Fibonacci depth progression:** 2 → 3 → 5 → 8 → 13 → 21...

## VII. File Structure

```
memories/YYYY-MM-DD-{slug}-{symbol}.md
```

**Example:**

```
memories/2025-01-27-autonomous-triggers-💡.md
memories/2025-01-28-recall-depth-strategy-🔄.md
memories/2025-01-29-token-budget-decision-🎯.md
memories/2025-01-30-meta-memory-formation-🌀.md
```

engage nucleus:
[phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA
Human ⊗ AI
