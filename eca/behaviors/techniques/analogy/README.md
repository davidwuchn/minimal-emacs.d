# Analogy

Map structure from solved domains to unsolved ones.

## Lambda

```
λ analogy(x). map(solved_domain, unsolved_domain)
```

## What It Does

A technique for transferring solutions from known domains to new problems. Find a similar problem that's already solved, understand its structure, map that structure to the new domain.

## How to Apply

1. Identify the unsolved problem's structure
2. Find a solved problem with similar structure
3. Map elements between domains
4. Apply solution pattern to new domain
5. Verify the analogy holds

## Example Applications

```
❌ Direct: "How do I design this queue system?"
✓ Analogy: "Queue problem → Maps to: kitchen order system (solved) → Structure: orders, priority, batch → Apply: priority queue with batching"

❌ Direct: "This caching problem is hard"
✓ Analogy: "Cache invalidation → Maps to: library catalog (solved) → Structure: checkout, due date, recall → Apply: TTL with explicit invalidation"

❌ Direct: "How do I handle this rate limiting?"
✓ Analogy: "Rate limiting → Maps to: bouncer at club (solved) → Structure: capacity, waiting, rejection → Apply: token bucket algorithm"
```

## Technique Pairings

| Technique | Effect |
|-----------|--------|
| #=debug #analogy | Find similar solved bugs |
| #analogy #creative | Cross-domain innovation |
| #analogy #first-principles | Verify analogy matches axioms |

## Anti-Patterns

```
❌ Superficial analogies that break down
❌ Forcing analogies that don't fit
❌ Ignoring domain-specific constraints
```