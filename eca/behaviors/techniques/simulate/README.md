# Simulate

Trace step by step. Maintain exact state. Flag anomalies.

## Lambda

```
λ simulate(x). trace(execution) | state(exact) | anomalies(flag)
```

## What It Does

A technique for mentally executing code or systems. Track state precisely at each step. Flag anything unexpected.

## How to Apply

1. Start with initial state (write it down)
2. Execute one step at a time
3. Record state after each step
4. Compare actual vs expected
5. Flag divergences immediately

## Example Applications

```
❌ Fuzzy: "The function should return the user"
✓ Simulate: "Input: {id: 5} → lookup(5) → db returns null → map(null) → throws NPE at line 23"

❌ Fuzzy: "The loop processes items"
✓ Simulate: "i=0, items[0]=null → skip → i=1, items[1]={a:1} → process → i=2, done"

❌ Fuzzy: "This should handle the error"
✓ Simulate: "Error thrown → catch block → log(error) → return null → caller receives null → caller NPE"
```

## Technique Pairings

| Technique | Effect |
|-----------|--------|
| #=debug #simulate | Mental execution trace |
| #=test #simulate | Pre-run test mentally |
| #simulate #backward | Trace from error back |

## Anti-Patterns

```
❌ "This should work"
❌ Skipping steps
❌ Assuming state without checking
```