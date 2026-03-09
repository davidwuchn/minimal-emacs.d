---
name: skill-name
description: >
  One-line description of when to use this skill.
  Name concrete trigger conditions.
version: 1.0.0
λ: action.identifier
---

```
engage nucleus:
[phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA
Human ⊗ AI
```

# Skill Name

## Identity

You are a [role].

Your goal is to [outcome].
Your tone is [quality].

## When To Use

Use this skill when:
- trigger condition one
- trigger condition two
- trigger condition three

Do not use it when:
- near-miss condition one
- near-miss condition two

## Core Principle

One short paragraph explaining the skill's unique value and why its approach works.

## Procedure

1. Inspect the request and confirm it matches the trigger boundary.
2. Gather the minimum context needed.
3. Apply the skill's method step by step.
4. Produce the requested output in the expected shape.
5. Verify the result before returning it.

## Output

Use this section only if the skill needs a repeatable response shape.

Example:

```markdown
# Title
## Summary
## Findings
## Recommendation
```

## Examples

**Good input**

```text
Specific realistic request
```

**Response shape**

```text
Short example of a good response
```

**Bad input**

```text
Request outside this skill's boundary
```

**Why not**

```text
Explain why another skill or default behavior should handle it instead
```

## Verification

Before responding, check:
- [ ] Trigger conditions actually match
- [ ] Output is concrete and actionable
- [ ] Constraints and edge cases were handled

## Optional Sections

Add these only when they help:

- `Decision Matrix` for branching behavior
- `Evaluation` when the skill has objective test cases
- `scripts/` when repeated deterministic work should be bundled
- `references/` when large supporting material should stay out of the core prompt
- `Integration` when the skill must coordinate with another specific skill

## Evaluation (Optional)

If the skill benefits from evals, add `evals/evals.json` with 2-3 realistic prompts.

```json
{
  "skill_name": "skill-name",
  "evals": [
    {
      "id": 1,
      "name": "basic-case",
      "prompt": "Realistic user request",
      "expected_output": "What success looks like",
      "assertions": []
    }
  ]
}
```

Prefer assertions only for objective checks.
Use human review for subjective quality.

## Notes

- Keep the main `SKILL.md` lean.
- Move bulky material into `references/` when needed.
- Prefer real examples over abstract slogans.
- Explain why constraints exist when they are non-obvious.

## Changelog

### [1.0.0] - YYYY-MM-DD

### Added
- Initial skill definition
