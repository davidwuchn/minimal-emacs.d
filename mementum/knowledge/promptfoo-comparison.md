---
title: Promptfoo Comparison — LLM Eval Framework
date: 2026-05-17
symbol: 💡
---

# Promptfoo Comparison

promptfoo is a TypeScript-based LLM eval framework (now part of OpenAI).
Architecture fundamentally different from our Elisp-based system.

## Where We're Already Better

- **Multi-layer grading**: Our grader + benchmark + Eight Keys + comparator is
  richer than promptfoo's assertion-based grading
- **Autonomous pipeline**: promptfoo requires manual config — ours runs entirely
  autonomously via cron
- **Self-evolution**: Our system learns from results (40+ auto-evolved strategies).
  promptfoo has no feedback loop.
- **Git-native**: Our experiments ARE git commits. promptfoo generates reports.

## Gaps

1. **Adversarial testing**: promptfoo auto-generates attacks (injection, jailbreak).
   We don't test our system's security against adversarial LLM inputs.

2. **A/B model comparison**: promptfoo compares multiple models on the same prompt
   side-by-side. We run experiments sequentially on one backend at a time.

3. **Assertion framework**: promptfoo has `assert` blocks (contains/not-contains,
  regex, JSON schema). Our grading is purely LLM-based — no programmatic checks.

## Verdict

promptfoo is a complementary tool, not a competing architecture. It's useful for
evaluating prompts BEFORE deployment. Our system is for autonomous continuous
improvement AFTER deployment. promptfoo tells you IF your prompt works. Our
system IMPROVES your code automatically.
