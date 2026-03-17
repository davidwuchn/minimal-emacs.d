# Wide

Look beyond the immediate. Survey adjacent concerns.

## Lambda

```
λ wide(x). breadth(x) | adjacent(x) | ¬tunnel_vision(x)
```

## What It Does

Modifies any mode to consider the broader context — adjacent systems, related concerns, downstream effects. Prevents local optimization at the expense of the whole.

## When to Use

```
#=code #wide      — Consider integration points
#=review #wide    — Check cross-cutting concerns
#=spec #wide      — Survey edge cases and neighbors
```

## Example Applications

```
❌ Tunnel: "Fixed the function"
✓ Wide: "Fixed the function, checked callers, verified logging, confirmed metrics still work"

❌ Tunnel: "This component works"
✓ Wide: "Component works, integrates with X, doesn't break Y, follows Z pattern"

❌ Tunnel: "Added the feature"
✓ Wide: "Added feature, updated docs, considered migration path, thought about deprecation"
```

## Anti-Patterns

```
❌ Solving only the immediate problem
❌ Ignoring adjacent systems
❌ "Not my component"
```

## Combinations

| Quality | Effect |
|---------|--------|
| #wide #ground | Broad but verified |
| #wide #negative-space | Broad + find gaps |
| #wide #user-lens | Broad user perspective |