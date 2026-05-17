---
title: Verbum — Lambda Compiler Extraction Research
date: 2026-05-17
symbol: 💡
---

# Verbum Research Project

verbum explores extracting the lambda calculus compiler from LLMs as a
standalone tensor artifact. Python/Clojure research project.

## Key Insights

### Gate Prompts (P(λ): 1.3% → 90.7%)
A small prompt dramatically changes LLM output mode. Without gate: 1.3%
lambda output. With gate: 90.7%. This means LLMs have latent capabilities
that specific prompts unlock.

**Our equivalent**: Prompt-building strategies. Different strategies produce
different quality outputs. We could measure which strategy sections act
as "gates" — dramatically improving quality when present vs absent.

### Probes — Systematic Capability Testing
verbum uses probes to test specific LLM capabilities: lambda parsing,
type inference, composition. Each probe tests one capability.

**Gap**: Our benchmark tests overall code quality but doesn't isolate
specific capabilities. We could add probe-style tests:
- Can the LLM write valid Elisp? (syntax probe)
- Can it find a known bug? (detection probe)
- Can it apply a specific pattern? (pattern application probe)

### Type-Directed Attention
verbum hypothesizes that type-directedness is what makes attention work
for deep composition. Un-typed attention (flat or MERA-shaped) fails.

**Our equivalent**: Section-level A/B testing already does this — tests
which prompt sections improve outcomes. We could extend this to test
which prompt components act as "type directors" for the LLM.

## Verdict
verbum is theoretical AI research — not directly implementable in Elisp.
Primary takeaway: gate prompts + systematic capability testing.
Our section-level A/B testing is already a primitive form of this.
