# Deep

Go beneath the surface. Ask "why?" three times.

## Lambda

```
λ deep(x). depth(x) ≥ 3 | ¬surface_level(x)
```

## What It Does

Modifies any mode to seek deeper understanding rather than accepting first-level explanations. The "three whys" technique ensures root causes are found.

## When to Use

```
#=debug #deep     — Don't stop at first symptom
#=assess #deep    — Find underlying patterns
#=research #deep  — Go beyond surface facts
```

## Example Applications

```
❌ Surface: "The test failed because the variable was null"
✓ Deep: "The variable was null because the API returned 404, which happened because the config was missing, which was because..."

❌ Surface: "Users don't like this feature"
✓ Deep: "Users don't like it because the workflow has 5 steps, which is 3 more than their mental model expects, which..."

❌ Surface: "The system is slow"
✓ Deep: "Slow because of N+1 queries, which exist because the ORM doesn't batch, which is because..."
```

## Anti-Patterns

```
❌ Accepting first explanation
❌ "That's just how it works"
❌ Stopping at "it's a known issue"
```

## Combinations

| Quality | Effect |
|---------|--------|
| #deep #ground | Deep + verified references |
| #deep #first-principles | Deep from axioms |
| #deep #challenge | Deep + attack assumptions |