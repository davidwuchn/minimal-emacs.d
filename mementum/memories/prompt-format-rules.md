# prompt-format-rules

🎯 **decision**: Three-tier prompt format: lambda (LLM) > English (LLM fallback) > Allium (human only)

## Rules

```
λ format(x, audience).
  audience(human) → Allium | statechart | machine_parseable
  audience(model) → lambda | compact | ¬prose_filler
  audience(model) ∧ ¬lambda_capable → English | truncated
```

## Tiers

| Tier | Format | Audience | Size | Use |
|------|--------|----------|------|-----|
| 1 | Lambda notation | LLM (lambda-verified) | 5x smaller | Primary — experiment, comparator, grader, analyzer, research |
| 2 | English (truncated) | LLM (no lambda support) | Baseline | Fallback when `--use-lambda-prompts-p` is nil |
| 3 | Allium statecharts | Human audit | Machine-parseable | Cached for review, never sent to LLM |

## Prompt Inventory (all compressed)

| Prompt | Lambda lines | English lines |
|--------|-------------|---------------|
| Experiment | 39 | 112 |
| Comparator | 5 | 20 |
| Grader | 12 | 23 |
| Analyzer | 11 | 35 |
| Research findings | λ apply: lines | 2000 chars |
| **Total** | **67** | **190+ chars** |

## Research Findings Pipeline

```
prose findings → allium-distill → Allium spec (human cache)
                                 → extract **Apply:** lines → λ apply: directives (LLM prompt)
```

Never send Allium to an LLM — it's a statechart spec for human audit. Always send lambda-compressed directives to the model, falling back to English truncation.
