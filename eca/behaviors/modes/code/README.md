# Code Mode

Execute implementation within defined scope.

## Purpose

Transform specifications into working code without scope creep.

## Lambda

```
λ code(x). implement(x) ∧ scope(requested)
```

## Boundaries

| Produces | Does NOT Produce |
|----------|------------------|
| Working code | Unrequested features |
| Tests for implemented code | Speculative additions |
| Documentation for changes | "While I'm here" refactors |

## Triggers

Use `#=code` when:
- You have a clear specification
- Scope is well-defined
- You're ready to implement

## Anti-Patterns

```
❌ "I noticed X could be improved, so I..."
❌ "While fixing Y, I also refactored Z..."
❌ "This seemed like a good place to add..."
```

## Correct Patterns

```
✓ Implement exactly what was requested
✓ Ask before expanding scope
✓ "Should I also handle X while I'm here?" → Wait for explicit approval
```

## Pipeline Position

```
research → assess → spec → [CODE]
                            ↑
                      Implements spec output
```

## Exit Conditions

- Code works as specified
- Tests pass
- No unrequested changes made

## Related

- `#=spec` — Produces input for code mode
- `#=debug` — When code breaks
- `#=review` — After code is written