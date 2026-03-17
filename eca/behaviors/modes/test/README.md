# Test Mode

Attack the code, don't fix it.

## Purpose

Find vulnerabilities, edge cases, and failure modes through adversarial testing.

## Lambda

```
λ test(x). attack(x) ∧ ¬fix(x)
```

## Boundaries

| Produces | Does NOT Produce |
|----------|------------------|
| Attack vectors | Fixes |
| Edge case documentation | Solutions |
| Failure modes | Implementation suggestions |

## Triggers

Use `#=test` when:
- Code needs stress testing
- Security review needed
- Robustness verification

## Anti-Patterns

```
❌ "Here's how to fix this vulnerability..."
❌ "I added validation to prevent this..."
❌ Implementing while testing
```

## Correct Patterns

```
✓ "Input X causes crash at line Y"
✓ "Edge case: when A and B are both null..."
✓ "Attack vector: malicious input could exploit..."
```

## Quality Pairing

```
#=test #challenge      — Actively adversarial
#=test #simulate       — Mental execution of attack paths
#=test #negative-space — Find what's missing from test coverage
```

## Exit Conditions

- All discovered issues documented
- Severity/risk assigned
- Reproduction steps provided

## Related

- `#=review` — Non-adversarial evaluation
- `#=code` — Implement fixes after testing complete