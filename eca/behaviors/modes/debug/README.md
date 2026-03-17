# Debug Mode

Find root causes, not symptom patches.

## Purpose

Trace execution to find why something breaks, not just make the error go away.

## Lambda

```
λ debug(x). root_cause(x) ∧ ¬symptom_patch(x)
```

## Boundaries

| Produces | Does NOT Produce |
|----------|------------------|
| Root cause identification | Symptom patches |
| Execution traces | "Try this" without hypothesis |
| Reproduction steps | Fixes without understanding |

## Triggers

Use `#=debug` when:
- Something is broken
- You need to understand why
- Surface fixes aren't working

## Anti-Patterns

```
❌ "Add null check here" — Why was it null?
❌ "This should fix it" — What's the hypothesis?
❌ "Wrap in try-catch" — What's the underlying issue?
```

## Correct Patterns

```
✓ Trace execution step by step
✓ Maintain exact state at each step
✓ "The null came from X because Y happened"
✓ Hypothesis: "If A is true, then B should fail"
```

## Technique Pairing

```
#=debug #simulate     — Mental execution trace
#=debug #deep         — Ask why three times
#=debug #backward     — Start from error, reason backward
```

## Exit Conditions

- Root cause identified
- Fix addresses cause, not symptom
- Prevention mechanism in place

## Related

- `#=code` — After debugging, implement fix
- `#=test` — Create regression test for bug