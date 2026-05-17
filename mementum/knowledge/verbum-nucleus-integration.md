---
title: Verbum + Nucleus Integration for Prompt Quality
date: 2026-05-17
symbol: 💡
---

# Verbum + Nucleus Integration

## The Connection

**verbum** researches extracting the lambda compiler from LLMs (P(λ) = 90.7%).
**nucleus** already HAS a working prompt compiler (prose ↔ EDN/λ).
Together they answer: how do we make our experiment prompts more effective?

## Practical Applications

### 1. Prompt Structure Scoring
nucleus's compiler evaluates whether prose compiles to a coherent structure.
Bad prompts produce sparse/error EDN. Good prompts produce rich statecharts.

We could add a "structure score" to our prompt builder:
- Build the prompt as usual
- Send it through a structure check (simplified version of nucleus compiler)
- Score the structure quality
- Use the score as a prompt quality metric

### 2. Hypothesis Validation
nucleus's lambda compiler can compile hypotheses to λ notation.
A well-formed λ hypothesis → more likely to produce a good experiment.

Example: "Adding nil validation to X will prevent crashes"
→ λ guard(x). nil_p(x) → error(x) | validate(x) → safe(x)

### 3. Gate Prompt Optimization
verbum shows gate prompts dramatically change output mode (1.3% → 90.7%).
Our prompt strategies already act as gates. We could:
- A/B test which strategy sections act as "strong gates"
- Amplify the gate sections that improve output quality
- Remove sections that weaken the gate effect

### 4. Section-Level Compilation Quality
For each section of our prompt (suggestions, self-evolution, topic-specific,
git-history, axis-performance, failure-patterns):
- Score how well each section "compiles"
- Keep sections that produce clean structure
- Drop or refactor sections that produce noise
