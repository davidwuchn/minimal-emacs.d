# three-format-rule

🎯 **decision**: Three formats, three audiences. Strict separation enforced by TDD regression tests.

## The Rule

```
λ format(x, audience).
  audience(llm)                 → lambda_notation | ¬english_prose | ¬allium_statechart | ¬edn_output_spec
  audience(behavioral_verify)   → allium_statechart | allium-check → issues
  audience(compiler_internal)   → edn | forge-lambda-fixed-point
```

## Format Boundaries

| Format | Goes to LLM? | Goes to Human? | Purpose |
|--------|-------------|----------------|---------|
| **Lambda notation** | Yes (primary) | Yes (source) | Prompt compression (5x) |
| **English prose** | No (banned) | Yes (legacy) | Phased out — all prompts now lambda |
| **Allium statecharts** | No (banned) | Yes (audit) | Behavioral verification, contradiction detection |
| **EDN** | No (banned) | No (banned) | Lambda compiler internal representation |

## Enforcement

TDD regression tests at `tests/test-gptel-tools-agent-regressions.el`:
- `no-english-prose-in-llm-prompts` — scans for CRITICAL/IMPORTANT/REQUIREMENTS in prompt strings
- `analyzer-prompt-is-lambda` — verifies λ select format
- `comparator-prompt-is-lambda` — verifies λ compare format
- `grader-prompt-is-lambda` — verifies λ grade format
- `experiment-prompt-is-lambda` — verifies no English section headers
- `research-for-prompt-extracts-apply` — verifies λ apply: extraction

## Remaining Violations (10 tracked, TDD regression test active)

1. inspection-thrash-contract (prompt-build.el:1077-1091) — 15 lines
2. Retry instructions (experiment-core.el:338-362) — 2×13 lines
3. Experiment-loop repair prompt (experiment-loop.el:162-207) — 46 lines
4. Agent-loop continuation (agent-loop.el:106-116) — defcustom
5. Agent-loop max-steps (agent-loop.el:123-134) — defcustom
6. Synthesis fallback (benchmark-llm.el:207) — ~20 lines
7. Synthesis fallback (agent-research.el:558-591) — ~30 lines
8. Digest analyst prompt (strategic.el:1191-1224) — 34 lines
9. Research analyst system prompt (strategic.el:1264) — 1 line
10. Strategy proposer template (strategy-evolver.el:608-731) — 124 lines

Violations tracked by `regression/three-format/no-english-prose-in-llm-prompts`.
Compressing these is an incremental task — each can be fixed independently.
