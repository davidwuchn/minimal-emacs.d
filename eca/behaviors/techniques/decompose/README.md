# Decompose

Break into independent subproblems. Find natural seams.

## Lambda

```
λ decompose(x). subproblems(independent) | seams(natural) | ¬monolith(x)
```

## What It Does

A technique for breaking complex problems into independent parts. Find the natural boundaries where concerns separate. Each subproblem should be solvable in isolation.

## How to Apply

1. Identify the monolithic problem
2. Find natural boundaries (data, responsibility, timing)
3. Check independence: can A be solved without B?
4. Solve each subproblem
5. Compose solutions

## Example Applications

```
❌ Monolith: "Build the user registration system"
✓ Decompose: "1) Validate input 2) Check uniqueness 3) Create user 4) Send email 5) Handle failures — each independent"

❌ Monolith: "Fix the performance issue"
✓ Decompose: "1) Profile to find bottleneck 2) Isolate the slow component 3) Optimize that component 4) Measure improvement"

❌ Monolith: "Refactor this module"
✓ Decompose: "1) Identify responsibilities 2) Extract each to separate function 3) Wire them together 4) Remove old code"
```

## Technique Pairings

| Technique | Effect |
|-----------|--------|
| #=spec #decompose | Break down requirements |
| #=code #decompose | Implement piece by piece |
| #decompose #contract | Define interfaces between parts |

## Anti-Patterns

```
❌ Creating dependencies between subproblems
❌ Subproblems that need each other's internals
❌ Breaking along arbitrary lines
```