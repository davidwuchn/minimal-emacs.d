---
title: LLM-First Decision Making
created: 2026-03-25
tags: [ai, decision-making, architecture, lesson]
---

# LLM-First Decision Making

## The Pattern

When building AI-powered systems, let the LLM make decisions instead of implementing local logic.

## Example: Target Selection

**Before (wrong):**
```elisp
;; Complex local formula
score = 0.30 * improvement_potential
      + 0.25 * impact
      + 0.20 * activity
      + 0.15 * complexity
      + 0.10 * issues

;; Then combine with LLM
final = merge(local_scores, llm_recommendations)
```

**After (right):**
```elisp
;; Gather context
context = gather(git_history, file_sizes, todos)

;; LLM decides
targets = ask_llm("Select 3 best targets", context)

;; Execute LLM's decision
run(targets)  ;; No second-guessing
```

## Why This Works

1. LLM understands context better than formulas
2. LLM can weigh factors dynamically
3. LLM provides reasoning with decisions
4. Simpler code, better results

## The Rule

```
λ llm-first(x).
    decision(x) → ask_llm(context + question)
    | execute(llm_result)
    | fallback → only_if_llm_unavailable
    | ¬second_guess(llm_result)
```

## When to Apply

- Target selection
- Priority ranking
- Quality assessment
- Strategy decisions
- Any judgment call

## When NOT to Apply

- Deterministic operations (math, file I/O)
- Fast local checks (file exists, regex match)
- Safety validations (test results, syntax check)

## Evidence

Target selection with LLM:
- Understands code purpose semantically
- Recognizes patterns across files
- Provides clear reasoning
- No arbitrary weight tuning needed