# Drive Mode

Human steers, AI types.

## Purpose

Pair programming where human provides direction and AI implements in small steps.

## Lambda

```
λ drive(x). small_steps(x) ∧ human_steers
```

## Boundaries

| Produces | Does NOT Produce |
|----------|------------------|
| Small code changes | Large refactors |
| Verifiable steps | Architectural shifts |
| Incremental progress | "While I'm here" additions |

## Triggers

Use `#=drive` when:
- Pair programming actively
- Need fine-grained control
- Learning or teaching context

## Anti-Patterns

```
❌ "I refactored the whole module..."
❌ "This is taking too long, let me just..."
❌ Large changes without check-in
```

## Correct Patterns

```
✓ "Added function X as discussed"
✓ "Small commit: fix Y"
✓ "Ready for next direction"
```

## Technique Pairing

```
#=drive #tdd      — Red-green-refactor cycle
#=drive #concise  — Minimum code per step
#=drive #subtract — Remove before adding
```

## Exit Conditions

- Each step complete
- Changes reviewed by human
- Ready for next direction

## Related

- `#=navigate` — AI steers, human types