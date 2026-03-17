# Record Mode

Document, don't invent.

## Purpose

Capture existing knowledge without creating new content.

## Lambda

```
λ record(x). capture(x) ∧ ¬invent(x)
```

## Boundaries

| Produces | Does NOT Produce |
|----------|------------------|
| Documentation | New ideas |
| Faithful representation | Improvements |
| Existing knowledge | Speculation |

## Triggers

Use `#=record` when:
- Documenting existing code
- Capturing decisions made
- Recording meeting outcomes

## Anti-Patterns

```
❌ "I improved the documentation by adding..."
❌ "While documenting, I noticed X should be..."
❌ "This could be better if..."
```

## Correct Patterns

```
✓ "Function X does Y (as implemented)"
✓ "Decision: chose A because B (as discussed)"
✓ "Current state: X, Y, Z (observed)"
```

## Quality Pairing

```
#=record #concise      — Minimum words
#=record #ground       — Verify accuracy
#=record #user-lens    — Document for audience
```

## Exit Conditions

- Existing state documented
- No new content invented
- Faithful to source

## Related

- `#=spec` — Create plans (new content)
- `#=code` — Implement (new content)