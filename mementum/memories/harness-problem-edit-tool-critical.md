---
title: The Harness Problem — Edit Tool Matters More Than Model
φ: 0.90
e: harness-problem-edit-tool-critical
λ: when.agent.fails.to.edit
Δ: 0.30
evidence: 5
sources:
  - https://blog.can.ac/2026/02/12/the-harness-problem/
  - Can Bölük / oh-my-pi benchmark
---

💡 The edit tool is the highest-leverage optimization point. A single harness change improved 15 models by 5-14 points — bigger than most model upgrades.

## Current Tools Are Broken

| Tool | Approach | Failure Mode |
|------|----------|-------------|
| Codex `apply_patch` | Diff string | 50.7% fail on non-OpenAI models (format-specific) |
| Claude `str_replace` | Exact text match | Must reproduce every character perfectly; whitespace sensitive |
| Cursor | Fine-tuned 70B merge model | Needed a **whole separate model** just for edits |
| Aider | Various formats | Format choice alone swung GPT-4 26%→59% |

**Common failure:** All require model to **reproduce content it already saw**. When it can't, edit fails.

## Hashline Solution

```
11:a3|function hello() {
22:f1|  return "world";
33:0e|}
```

Edit by hash reference: "Replace line `2:f1`" — no need to reproduce text or whitespace.

**Results:** Grok Fast 1: 6.7%→68.3% (10×). MiniMax doubled. Gemini +5-14pp, -20% tokens.

## Vendor Politics

Anthropic blocked OpenCode. Google banned the author for benchmarking.

> "No vendor will optimize harness for competitors' models."

**OV5 implication:** We must own our harness. The edit tool is not a commodity — it's infrastructure.

## Integration

- `edit` tool could use hashline-style anchors
- `apply_patch` failures in logs may be harness, not model
- Validates deterministic-first principle (S4)
- Lambda notation = same principle: stable anchors vs reproduction
