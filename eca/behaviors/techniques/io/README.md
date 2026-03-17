# IO

Pure core, impure shell. Own every side effect.

## Lambda

```
λ io(x). core(pure) ∧ shell(impure) | side_effects(owned)
```

## What It Does

A technique for separating pure logic from side effects. The core has no I/O, no mutation, no randomness — only computation. The shell handles all I/O and calls the core.

## How to Apply

1. Identify side effects (I/O, mutation, randomness, time)
2. Extract pure computation into core functions
3. Wrap core with shell that handles I/O
4. Track every side effect explicitly

## Example Applications

```
❌ Mixed: "Function reads config, processes data, writes result"
✓ IO: "Core: process(data, config) → result (pure) | Shell: read_config() → process() → write_result()"

❌ Mixed: "Handler queries DB, transforms, returns response"
✓ IO: "Core: transform(data, params) → result (pure) | Shell: query_db() → transform() → json_response()"

❌ Mixed: "Validate and save user in one function"
✓ IO: "Core: validate(user) → errors | valid(user) → bool (pure) | Shell: validate() → if valid: save()"
```

## Technique Pairings

| Technique | Effect |
|-----------|--------|
| #=code #io | Separate pure from impure |
| #=test #io | Test core without I/O |
| #io #contract | Define pure core contracts |

## Anti-Patterns

```
❌ Side effects scattered throughout
❌ Hidden I/O in "utility" functions
❌ Untestable impure code
```