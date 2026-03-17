# Contract

Pre/post/invariant. Who owes what to whom.

## Lambda

```
λ contract(x). precondition ∧ postcondition ∧ invariant
```

## What It Does

A technique for defining explicit agreements between components. Preconditions: what the caller must provide. Postconditions: what the callee guarantees. Invariants: what always holds.

## How to Apply

1. Define preconditions: what must be true before?
2. Define postconditions: what will be true after?
3. Define invariants: what must always be true?
4. Document and enforce these contracts

## Example Applications

```
❌ Implicit: "This function expects a user object"
✓ Contract: "Pre: user.id is non-empty string | Post: returns User or throws NotFound | Inv: user object unchanged"

❌ Implicit: "The function processes the payment"
✓ Contract: "Pre: amount > 0, card.valid | Post: returns Transaction(id, status) | Inv: no double-charge"

❌ Implicit: "Save returns success or failure"
✓ Contract: "Pre: data has required fields | Post: returns id on success, throws Validation on invalid | Inv: id unique"
```

## Technique Pairings

| Technique | Effect |
|-----------|--------|
| #=spec #contract | Define API contracts |
| #=test #contract | Test contract enforcement |
| #contract #decompose | Define boundaries between parts |

## Anti-Patterns

```
❌ Undocumented assumptions
❌ Vague error conditions
❌ Contracts that change silently
```