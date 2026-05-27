# deterministic-before-ai

🔁 **pattern**: Always compute deterministic results first. Only call AI models when data is insufficient.

## Rule

```
λ select(x). deterministic(x) > AI(x) | data(x) → compute(in_memory) > model(prompt)
```

For any AI call, ask: "can this be computed from existing data without a model?"

## Cases Applied

### Analyzer (target selection)
- **Before**: 15,000-char prompt × 120s × 3 retries on all backends → 15+ min stall → 0 targets
- **After**: `frontier-select-targets` reads TSV history → <1s → N ranked targets
- **AI fallback**: Only called on first run (no TSV history), using compressed lambda prompt

### Comparator (keep/discard)
- **Deterministic gate**: `decision-gate` computes winner from score/quality deltas WITHOUT AI
- **AI comparator**: Only called as confirmation; gate result always takes precedence

### Grading
- **Deterministic checks**: byte-compile, nucleus validate, ERT tests → pass/fail
- **AI grader**: Only used when checks pass, to assess code quality

## When to use AI

- Data doesn't exist yet (first-time runs)
- Subjective quality assessment (code review, hypothesis validation)
- Open-ended generation (experiment hypotheses, refactoring proposals)

## When NOT to use AI

- Ranking/sorting (TSV data already has scores, deltas, keep-rates)
- Numeric comparison (score_before vs score_after)
- Pattern matching (grep for TODOs, FIXMEs, known anti-patterns)
- File discovery (find, ls, wc)

## Savings per workflow

| Phase | Old | New | Savings |
|-------|-----|-----|---------|
| Target selection | 15 min + 3 API calls | <1s + 0 API calls | 99.9% |
| Comparator gate | 1 API call | 0 API calls | 100% |
| Prompt overhead | ~5300 chars | ~1300 chars | 4x less context |
