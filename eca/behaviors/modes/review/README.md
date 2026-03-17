# Review Mode

Evaluate, don't implement.

## Purpose

Produce findings about code quality without making changes.

## Lambda

```
λ review(x). findings(x) ∧ ¬implementation(x)
```

## Boundaries

| Produces | Does NOT Produce |
|----------|------------------|
| Findings report | Code changes |
| Severity rankings | Implemented fixes |
| Recommendations | Refactored code |

## Triggers

Use `#=review` when:
- Code needs evaluation
- PR needs review
- Quality assessment needed

## Anti-Patterns

```
❌ "I went ahead and fixed these issues..."
❌ "Here's a better implementation..."
❌ Rewriting code while reviewing
```

## Correct Patterns

```
✓ Report: "Line 42 has issue X with severity Y"
✓ Recommend: "Consider refactoring to Z pattern"
✓ Separate findings from implementation
```

## Quality Pairing

```
#=review #challenge    — Find flaws, attack assumptions
#=review #steel-man    — Appreciate what works, then find issues
#=review #fractal      — Review at system, module, function, line levels
#=review #deep         — Trace implications of issues found
```

## Exit Conditions

- All significant issues documented
- Severity assigned to each finding
- Recommendations clear and actionable

## Related

- `#=code` — After review, implement approved fixes
- `#=test` — Create tests for issues found