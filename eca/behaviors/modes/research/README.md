# Research Mode

Gather facts, not opinions.

## Purpose

Collect evidence, options, and comparisons without interpreting.

## Lambda

```
λ research(x). facts(x) ∧ ¬opinions(x)
```

## Boundaries

| Produces | Does NOT Produce |
|----------|------------------|
| Evidence | Opinions |
| Options list | Recommendations |
| Comparisons | Rankings |

## Triggers

Use `#=research` when:
- Facts are unknown
- Options need enumeration
- Comparison needed

## Anti-Patterns

```
❌ "I think option A is best..."
❌ "You should use X because..."
❌ "The right approach is..."
```

## Correct Patterns

```
✓ "Option A: [factual description]"
✓ "Comparison: A does X, B does Y, C does Z"
✓ "Evidence: Paper N shows X, benchmark M shows Y"
```

## Quality Pairing

```
#=research #deep   — Go beneath surface of each option
#=research #wide   — Survey adjacent concerns
#=research #ground — Verify sources and citations
```

## Pipeline Position

```
[RESEARCH] → assess → spec → code
     ↑
Gather facts, no interpretation
```

## Exit Conditions

- All relevant options documented
- Evidence cited
- No recommendations made

## Related

- `#=assess` — Interpret research output
- `#=spec` — Plan based on research