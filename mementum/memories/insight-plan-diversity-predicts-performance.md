---
title: "Plan diversity directly predicts performance gains"
date: 2026-06-10
symbol: 💡
---

PlanSearch (arXiv:2409.03733) proves that performance gains from search are a **direct function of plan diversity**.

The mechanism: LLMs lack output diversity when repeatedly sampling code — they generate similar incorrect solutions. Searching over diverse natural language plans (not code) breaks this pattern.

**Key finding:** You can predict how much search will help by measuring plan diversity *before* implementation. If plans are diverse, search helps a lot. If plans are similar, search barely helps.

**OV5 implication:** We generate one hypothesis per target per cycle. No diversity metric. No plan-level search. We're doing repeated sampling of similar approaches — exactly PlanSearch's identified failure mode.

**Actionable:** Before implementing a hypothesis, generate 3-5 diverse plans, measure their diversity, pick the most different ones. This is cheap (NL plans, not code) and directly predicts whether the experiment will succeed.
