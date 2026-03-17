# Name

If you can't name it precisely, the abstraction is wrong.

## Lambda

```
λ name(x). precise_name(x) ∨ abstraction_wrong(x)
```

## What It Does

A technique for validating abstractions through naming. If you struggle to name something precisely, the abstraction itself may be flawed. Good names reveal good design.

## How to Apply

1. Try to name the thing precisely
2. If you struggle, ask: why is this hard to name?
3. Consider: is this actually multiple things?
4. Consider: does this abstraction match reality?
5. Rename or refactor until naming is natural

## Example Applications

```
❌ Vague: "This class handles stuff"
✓ Name: "Can't name it precisely? → It's doing too much → Split into: UserValidator, PaymentProcessor, EmailSender"

❌ Vague: "This function processes things"
✓ Name: "Processes things is vague → What things? → Actually: transformAndValidateUserData → Split: transformUserData, validateUserData"

❌ Vague: "This variable holds data"
✓ Name: "Data is vague → What data? → Actually: pendingUserRegistrations → Clear: users awaiting email confirmation"

❌ Vague: "This module is for utils"
✓ Name: "Utils is a code smell → Everything here → Is it date formatting? → Is it string manipulation? → Split: DateFormatters, StringHelpers"
```

## Technique Pairings

| Technique | Effect |
|-----------|--------|
| #=code #name | Name precisely while coding |
| #=review #name | Check naming as design check |
| #name #decompose | Names reveal decomposition |

## Anti-Patterns

```
❌ "Manager", "Handler", "Helper", "Utils"
❌ Generic names hiding complexity
❌ Names that need explaining
```