# TDD

Red → green → refactor. One behavior at a time.

## Lambda

```
λ tdd(x). red → green → refactor | behavior(one)
```

## What It Does

A technique for driving design through tests. Write a failing test first, make it pass with minimal code, then refactor. Focus on one behavior at a time.

## How to Apply

1. **Red**: Write a failing test for one behavior
2. **Green**: Write minimal code to make test pass
3. **Refactor**: Improve code while keeping test green
4. Repeat for next behavior

## Example Applications

```
❌ Write tests after: "Here's the implementation, now I'll test it"
✓ TDD: "Test: should reject null input → FAIL → Add null check → PASS → Refactor to validation function → PASS"

❌ Big batch: "I'll test all the cases at once"
✓ TDD: "Test: empty list → PASS → Test: single item → FAIL → Fix → PASS → Test: multiple items..."

❌ Skip refactor: "It works, moving on"
✓ TDD: "Test passes → Can I simplify? → Extract helper → Still passes → Can I name better? → Rename → Still passes"
```

## Technique Pairings

| Technique | Effect |
|-----------|--------|
| #=code #tdd | Test-driven implementation |
| #=test #tdd | Write tests first |
| #tdd #decompose | One test per decomposed part |

## Anti-Patterns

```
❌ Writing implementation first
❌ Writing multiple tests before any pass
❌ Skipping refactor phase
```