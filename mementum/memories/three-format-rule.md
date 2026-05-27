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

## Remaining Violations

10 English prose prompts still need compression (from audit):
1. inspection-thrash contract (prompt-build.el)
2. Retry instructions (experiment-core.el, 2 dup blocks)
3. Experiment-loop repair prompt (experiment-loop.el)
4. Agent-loop continuation (agent-loop.el)
5. Agent-loop max-steps (agent-loop.el)
6. Synthesis fallback (benchmark-llm.el)
7. Synthesis fallback (agent-research.el)
8. Digest analyst prompt (strategic.el)
9. Research analyst system prompt (strategic.el)
10. Strategy proposer template (strategy-evolver.el)

The lambda format ALREADY applied to experiment, comparator, grader, analyzer prompts.
