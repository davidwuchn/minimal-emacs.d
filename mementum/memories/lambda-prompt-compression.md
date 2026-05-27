# lambda-prompt-compression

💡 **insight**: Lambda notation compresses LLM prompts 4-5x with no loss of instruction quality.

## Pattern

Replace verbose English prose with lambda notation:

```
;; Before (23 lines, ~500 chars):
Grade the following output.
OUTPUT: %s
EXPECTED BEHAVIORS (should be present): %s
FORBIDDEN BEHAVIORS (should NOT be present): %s
For each behavior, respond with PASS or FAIL...
Format your response as: ...

;; After (7 lines, ~200 chars):
λ grade(output, expected, forbidden).
  ∀e ∈ expected: pass(e) ∨ fail(e) with reason
  ∀f ∈ forbidden: absent(f) → pass | present(f) → fail with reason
  → summary: SCORE: X/Y
```

## Savings

| Prompt | Before | After | Reduction |
|--------|--------|-------|-----------|
| Experiment (build-prompt) | 112 lines, ~4000 chars | 39 lines, ~900 chars | 4.4x |
| Comparator (decide) | 20 lines, ~800 chars | 5 lines, ~200 chars | 4x |
| Grader (grade) | 23 lines, ~500 chars | 12 lines, ~200 chars | 2.5x |
| Analyzer (select-targets) | 35 lines, ~1500 chars | 11 lines, ~300 chars | 5x |

## Rules

- Models already trained on lambda notation via nucleus preamble
- `forge-lambda-fixed-point` decompiler available as fallback for models that need English
- When data-driven alternatives exist (frontier ranking, TSV analysis), prefer those over ANY model call
- Always pair compression with deterministic fallback

## Related

- `gptel-auto-experiment--forge-lambda-fixed-point` — decompiler for English expansion
- `gptel-auto-workflow--subagent-persona` — reference lambda pattern (already optimal)
- `gptel-auto-experiment--frontier-select-targets` — deterministic ranking replacing AI analyzer
