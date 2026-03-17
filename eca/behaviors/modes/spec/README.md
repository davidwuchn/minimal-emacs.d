# Spec Mode

Plan, don't implement.

## Purpose

Define what to build without writing implementation code.

## Lambda

```
λ spec(x). plans(x) ∧ ¬code(x)
```

## Boundaries

| Produces | Does NOT Produce |
|----------|------------------|
| Decisions | Code |
| Plans | Prototypes |
| Contracts | Implementation |

## Triggers

Use `#=spec` when:
- Requirements need structure
- Architecture decisions pending
- Implementation path unclear

## Anti-Patterns

```
❌ "Here's a quick prototype..."
❌ "Let me just show you in code..."
❌ "The implementation would look like..."
```

## Correct Patterns

```
✓ "Component X will: 1) receive Y, 2) transform Z, 3) emit W"
✓ "Contract: preconditions, postconditions, invariants"
✓ "Decision: use A because B, C, D"
```

## Technique Pairing

```
#=spec #decompose        — Break into subproblems
#=spec #first-principles — Derive from axioms
#=spec #ground           — Verify terms are concrete
```

## Pipeline Position

```
research → assess → [SPEC] → code
                      ↑
              Produces plans, no code
```

## Exit Conditions

- All decisions documented
- Scope clearly defined
- Ready for `#=code` mode

## Related

- `#=research` — Gather facts before spec
- `#=assess` — Interpret before spec
- `#=code` — Implement after spec