# Recursive

Apply process to its own output. Iterate until fixpoint.

## Lambda

```
λ recursive(x). process(output(x)) → fixpoint
```

## What It Does

A technique for refinement through iteration. Apply the same process repeatedly until the output stops changing (fixpoint). Each iteration improves on the previous.

## How to Apply

1. Apply process to input
2. Check if output changed meaningfully
3. If changed, apply process to output
4. Repeat until fixpoint (no meaningful change)

## Example Applications

```
❌ Single-pass: "Review the code once"
✓ Recursive: "Review → find issues → fix → review again → find more issues → fix → review → no new issues (fixpoint)"

❌ Single-pass: "Explain the system"
✓ Recursive: "Explain → identify gaps → explain again with gaps filled → identify remaining gaps → explain → complete (fixpoint)"

❌ Single-pass: "Simplify this function"
✓ Recursive: "Simplify → can simplify more? → yes → simplify → can simplify more? → no (fixpoint)"
```

## Technique Pairings

| Technique | Effect |
|-----------|--------|
| #=review #recursive | Multiple review passes |
| #recursive #decompose | Decompose recursively |
| #recursive #deep | Go deeper each iteration |

## Anti-Patterns

```
❌ Stopping after one iteration
❌ Infinite loops (no fixpoint check)
❌ Accepting degraded output
```