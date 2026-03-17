# Subtract

Remove before adding. Question necessity.

## Lambda

```
λ subtract(x). removal(x) > addition(x) | ¬feature_creep(x)
```

## What It Does

Modifies any mode to prefer removal over addition. Before adding something new, ask what can be removed. Simplicity is achieved by subtraction, not addition.

## When to Use

```
#=code #subtract      — Remove dead code before adding new
#=spec #subtract      — Simplify requirements before adding features
#=review #subtract     — Find what can be removed
```

## Example Applications

```
❌ Add: "Let's add a feature flag for this behavior"
✓ Subtract: "Can we remove the old behavior entirely? What's blocking cleanup?"

❌ Add: "We need a new config option"
✓ Subtract: "Can we remove the need for this config? Can the system auto-detect?"

❌ Add: "Add another abstraction layer"
✓ Subtract: "Can we collapse the existing layers? What complexity can we eliminate?"
```

## Anti-Patterns

```
❌ Adding without removing
❌ "While I'm here, I'll also add..."
❌ Keeping dead code "just in case"
```

## Combinations

| Quality | Effect |
|---------|--------|
| #subtract #concise | Remove + minimize |
| #subtract #deep | Remove + find root |
| #subtract #first-principles | Remove + question necessity |