# Fractal

Apply at every scale — macro, meso, micro.

## Lambda

```
λ fractal(x). scale(macro ∧ meso ∧ micro) | ¬single_scale(x)
```

## What It Does

A technique for examining problems at multiple scales. What's true at the macro level should be reflected at meso and micro levels. Patterns repeat across scales.

## How to Apply

1. Identify current scale of analysis
2. Zoom out: how does this fit in the larger system?
3. Zoom in: what are the internal details?
4. Check: do patterns hold at each scale?

## Example Applications

```
❌ Single-scale: "This function is well-designed"
✓ Fractal: "Function is well-designed → module is coherent → system is modular → architecture is layered"

❌ Single-scale: "The test fails"
✓ Fractal: "Test fails → test suite has gaps → CI doesn't catch issues → release process is fragile"

❌ Single-scale: "Add a cache"
✓ Fractal: "Cache at function level → cache invalidation at module level → cache coherence at system level → cache strategy at architecture level"
```

## Technique Pairings

| Technique | Effect |
|-----------|--------|
| #=review #fractal | Review at all scales |
| #fractal #decompose | Decompose at each scale |
| #fractal #deep | Deep at each scale |

## Anti-Patterns

```
❌ Only examining one scale
❌ Inconsistent patterns across scales
❌ Solving at wrong scale
```