# First-Principles

Derive from axioms, not patterns or conventions.

## Lambda

```
λ first_principles(x). derive(x, axioms) | ¬pattern_match(x)
```

## What It Does

Modifies any mode to reason from fundamental truths rather than copying existing patterns. Ask "what must be true?" rather than "how is it usually done?"

## When to Use

```
#=spec #first-principles    — Design from requirements, not patterns
#=assess #first-principles  — Evaluate from fundamentals
#=debug #first-principles   — Trace to root causes
```

## Example Applications

```
❌ Pattern: "We'll use microservices because that's what Netflix does"
✓ First-principles: "What are our scaling needs? Deployment constraints? Team structure? From these axioms, monolith-with-modules fits better"

❌ Pattern: "Add a cache because that's standard practice"
✓ First-principles: "What's the actual read/write ratio? Latency budget? Consistency requirements? A cache adds complexity — do we need it?"

❌ Pattern: "Use React because it's popular"
✓ First-principles: "What UI interactions do we need? What's our rendering model? Team expertise? From these, React might be overkill"
```

## Anti-Patterns

```
❌ "This is how we've always done it"
❌ "Industry standard is..."
❌ "Best practice says..."
```

## Combinations

| Quality | Effect |
|---------|--------|
| #first-principles #challenge | Derive then attack |
| #first-principles #deep | Deep axiomatic reasoning |
| #first-principles #creative | Novel derivations |