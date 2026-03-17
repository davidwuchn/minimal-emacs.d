# Assess Mode

Interpret, don't prescribe.

## Purpose

Provide insights and tradeoffs without recommending action.

## Lambda

```
λ assess(x). insight(x) ∧ ¬action(x)
```

## Boundaries

| Produces | Does NOT Produce |
|----------|------------------|
| Insights | Directives |
| Tradeoffs | Action plans |
| Implications | Implementation steps |

## Triggers

Use `#=assess` when:
- Interpretation needed
- Tradeoff analysis required
- Implications unclear

## Anti-Patterns

```
❌ "You should do X..."
❌ "The next step is Y..."
❌ "I recommend implementing Z..."
```

## Correct Patterns

```
✓ "Option A trades X for Y"
✓ "Choosing X implies Y and Z"
✓ "The risk of A is B; the risk of C is D"
```

## Quality Pairing

```
#=assess #wide        — Survey implications broadly
#=assess #challenge   — Find flaws in each option
#=assess #steel-man   — Strengthen before evaluating
```

## Pipeline Position

```
research → [ASSESS] → spec → code
               ↑
        Interpret without prescribing
```

## Exit Conditions

- All significant tradeoffs documented
- Implications clear
- No action directives given

## Related

- `#=research` — Provides input for assessment
- `#=spec` — Receives output for planning