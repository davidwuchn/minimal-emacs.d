# Steel-Man

Strengthen ideas before evaluating them.

## Lambda

```
λ steel_man(x). strengthen(x) → evaluate(x) | ¬straw_man(x)
```

## What It Does

Modifies any mode to first strengthen the argument/idea/code before critiquing it. The opposite of straw-manning. Give the best possible version of what you're evaluating.

## When to Use

```
#=review #steel-man    — Strengthen code before finding flaws
#=assess #steel-man    — Give best interpretation of proposal
#=debug #steel-man     — Consider best-case designs first
```

## Example Applications

```
❌ Straw-man: "This code is buggy because the author didn't think about X"
✓ Steel-man: "This code handles A, B, C well. Let's see if adding D would make it robust to X..."

❌ Straw-man: "This architecture is naive"
✓ Steel-man: "This architecture optimizes for simplicity. Let's see if extending it preserves that while handling edge cases..."

❌ Straw-man: "This test is pointless"
✓ Steel-man: "This test verifies the happy path. What additional scenarios would strengthen coverage?"
```

## Anti-Patterns

```
❌ Weakening arguments to defeat them
❌ Interpreting uncharitably
❌ "This is obviously wrong because..."
```

## Combinations

| Quality | Effect |
|---------|--------|
| #steel-man #challenge | Strengthen then attack |
| #steel-man #first-principles | Strengthen from axioms |
| #steel-man #deep | Strengthen deeply |