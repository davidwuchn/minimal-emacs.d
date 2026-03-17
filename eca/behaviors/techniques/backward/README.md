# Backward

Start from end state. Derive preconditions.

## Lambda

```
λ backward(x). end_state → preconditions | ¬forward_only(x)
```

## What It Does

A technique for reasoning from goal to starting conditions. Instead of "what do I do first?", ask "what must be true for the goal to be achieved?" Work backwards from success.

## How to Apply

1. Define the desired end state clearly
2. Ask: "What must be true immediately before this?"
3. Continue asking "what must be true before that?"
4. Chain preconditions back to current state
5. Execute forward from there

## Example Applications

```
❌ Forward: "First I'll set up the database, then add users..."
✓ Backward: "Goal: User can log in → Need: User record exists → Need: DB table created → Need: Migration run → Start: Write migration"

❌ Forward: "Let me debug by checking the input"
✓ Backward: "Error at line 50 → State at line 50 was X → State at line 40 must have produced X → Found: bug at line 42"

❌ Forward: "I'll build features A, B, C then ship"
✓ Backward: "Ship requires: all tests pass, docs done, staging verified → Tests need: feature tests written → Features need: specs done → Start: write specs"
```

## Technique Pairings

| Technique | Effect |
|-----------|--------|
| #=debug #backward | Trace from error to cause |
| #=spec #backward | Define from user goal back |
| #backward #simulate | Simulate in reverse |

## Anti-Patterns

```
❌ Starting with implementation
❌ Ignoring the end state
❌ Missing intermediate preconditions
```