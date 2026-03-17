# Temporal

Consider all orderings. Find the ones that break.

## Lambda

```
λ temporal(x). orderings(all) → break(find)
```

## What It Does

A technique for finding bugs in concurrent or sequential systems. Consider all possible orderings of events. Find the ones that cause failures.

## How to Apply

1. Identify all events/operations in the system
2. List possible orderings (especially edge cases)
3. For each ordering, trace what happens
4. Find orderings that cause failures
5. Design to handle or prevent them

## Example Applications

```
❌ Sequential-only: "The code works when called in order"
✓ Temporal: "Works: create → update → delete | Breaks: create → delete → update (404) | Breaks: update → create (overwrite)"

❌ Sequential-only: "Tests pass when run one at a time"
✓ Temporal: "Pass: test A → test B | Breaks: test A ∥ test B (shared state) | Fix: isolate test state"

❌ Sequential-only: "Feature works for single user"
✓ Temporal: "Works: user1 saves → user2 reads | Breaks: user1 saves ∥ user2 reads (race) | Breaks: user1 saves → user1 saves → user2 reads (lost update)"
```

## Technique Pairings

| Technique | Effect |
|-----------|--------|
| #=debug #temporal | Find race conditions |
| #=test #temporal | Test orderings |
| #temporal #simulate | Simulate each ordering |

## Anti-Patterns

```
❌ Assuming operations happen in order
❌ Ignoring concurrent access
❌ Not testing edge-case orderings
```