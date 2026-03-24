# Mementum State

> Last session: 2026-03-24

## Session Summary

### Commits

| Hash | Description |
|------|-------------|
| `241b706` | TDD: code quality scoring + test coverage |
| `065a0c0` | LLM degradation detection |
| `117d4b3` | Memory: llm-degradation-detection |
| `156f08d` | Fix vc-git-root batch mode compatibility |

### New Functions

| Function | Purpose |
|----------|---------|
| `gptel-benchmark--code-quality-score` | Docstring coverage (0.0-1.0) |
| `gptel-benchmark--detect-llm-degradation` | Detect off-topic/repetition/loops |
| `gptel-auto-experiment--code-quality-score` | Integration with auto-experiment |

### Test Status

```
Isolation tests (pass individually):
- grader/*         19/19 ✓
- retry/*          32/32 ✓
- git-grep/*        3/3 ✓
- find-usages/*     2/2 ✓
- agent-loop/*     18/18 ✓

Full suite: 1051/1115 (33 fail due to test isolation)
```

### Known Issue: Test Isolation

Tests pass in isolation but fail when run together. Cause: global state pollution between tests. Not a code bug.

### LLM Degradation Detection

```elisp
(gptel-benchmark--detect-llm-degradation 
 response 
 expected-keywords)
;; => (:degraded-p t :reason "I apologize" :score 0.67)
```

Detects:
1. Forbidden keywords (apologies, AI self-reference)
2. Off-topic (missing expected keywords)

---

## λ Summary

```
λ tdd. red → green → refactor
λ detect. forbidden + missing_expected = degradation
λ fix. vc-git-root → file-directory-p (batch mode)
λ learn. tests pass in isolation ≠ pass together
```