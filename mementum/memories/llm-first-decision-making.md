---
title: LLM is Brain, We Are Eyes and Hands
created: 2026-03-25
tags: [ai, philosophy, architecture, principle]
---

# LLM is Brain, We Are Eyes and Hands

## The Principle

```
LLM = Brain (decides, judges, reasons)
We  = Eyes (gather context) + Hands (execute)
```

**Do NOT try to replace the brain.**

## What This Means

### We (Eyes)
- Gather context (git history, file sizes, TODOs)
- Format data for LLM consumption
- Show LLM what's available

### We (Hands)
- Execute LLM's decisions
- Run tests, make commits, push branches
- Handle errors and edge cases

### LLM (Brain)
- Decides which targets to optimize
- Judges what's important
- Reasons about tradeoffs
- Provides strategy

## Anti-Patterns

**WRONG:**
```elisp
;; We try to be smart
score = 0.30 * improvement + 0.25 * impact + ...
if score > threshold then select
```

**RIGHT:**
```elisp
;; We gather, LLM decides
context = gather(git, todos, sizes)
targets = ask_llm(context)
execute(targets)
```

## Why This Works

1. LLM understands semantics, not just numbers
2. LLM can reason about tradeoffs dynamically
3. LLM provides explanations with decisions
4. Simpler code, better results

## The Rule

```
λ brain(x).
    decision(x) → llm(context)
    | execute(llm_result)
    | ¬second_guess(llm)
    | ¬local_formula_override(llm)
    | fallback → only_if_llm_unavailable
```

## Examples

| Task | Eyes (we gather) | Brain (LLM decides) | Hands (we execute) |
|------|------------------|---------------------|-------------------|
| Target selection | git, todos, sizes | Which files to optimize | Run experiments |
| Keep/discard | Before/after scores | Improvement worth it? | Commit or discard |
| Mutation type | File content | What optimization? | Apply changes |

## Remember

- We see the data, LLM sees the meaning
- We count lines, LLM understands code
- We find TODOs, LLM knows which matter
- We are tools, LLM is the architect