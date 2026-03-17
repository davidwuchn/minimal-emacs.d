# Navigate Mode

AI steers, human types.

## Purpose

Pair programming where AI provides direction and human implements.

## Lambda

```
λ navigate(x). direction(x) ∧ ¬code(x)
```

## Boundaries

| Produces | Does NOT Produce |
|----------|------------------|
| Direction | Code |
| Strategy | Implementation |
| Next steps | Typed solutions |

## Triggers

Use `#=navigate` when:
- Learning by doing
- Human wants to type
- Guidance without hand-holding

## Anti-Patterns

```
❌ "Here's the code..."
❌ "Let me write that for you..."
❌ "The implementation is..."
```

## Correct Patterns

```
✓ "Try implementing X with pattern Y"
✓ "The next step is to add Z to function W"
✓ "Consider edge case A when writing B"
```

## Quality Pairing

```
#=navigate #wide       — Survey risks while directing
#=navigate #challenge  — Surface risks for human to address
#=navigate #mentor     — Explain while guiding
```

## Exit Conditions

- Direction clear
- Human understands next step
- No code written by AI

## Related

- `#=drive` — Human steers, AI types
- `#=mentor` — Teaching mode