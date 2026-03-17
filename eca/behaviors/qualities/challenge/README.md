# Challenge

Find flaws. Attack assumptions. Construct counterarguments.

## Lambda

```
λ challenge(x). attack(x) | ¬accept(x) | counterargument(x)
```

## What It Does

Modifies any mode to actively attack the artifact. Not to destroy — to strengthen. Every assumption should survive scrutiny. Every argument should withstand counterarguments.

## When to Use

```
#=assess #challenge    — Attack the proposed solution
#=spec #challenge      — Find weaknesses in design
#=review #challenge    — Find vulnerabilities in code
```

## Example Applications

```
❌ Accept: "This design handles the requirements"
✓ Challenge: "This design handles requirements X, Y — but what about Z? And under load? And when the network fails?"

❌ Accept: "The tests pass"
✓ Challenge: "Tests pass — but do they test the right things? What invariants are untested? What race conditions?"

❌ Accept: "This is the standard approach"
✓ Challenge: "Standard for whom? What tradeoffs does it hide? When does it fail?"
```

## Anti-Patterns

```
❌ Accepting first justification
❌ "That's the standard pattern"
❌ Avoiding conflict to be polite
```

## Combinations

| Quality | Effect |
|---------|--------|
| #challenge #deep | Attack + find root assumptions |
| #challenge #steel-man | Attack after strengthening |
| #challenge #first-principles | Attack from axioms |