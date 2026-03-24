# Mementum State

> Last session: 2026-03-24

## Session Summary: TDD + LLM Quality Detection + Test Fixes

### Commits (6)

| Hash | Description |
|------|-------------|
| `1a69411` | Fix test isolation issues |
| `19e4077` | test-isolation-issue memory |
| `156f08d` | Fix vc-git-root batch mode compatibility |
| `117d4b3` | llm-degradation-detection memory |
| `065a0c0` | LLM degradation detection |
| `241b706` | TDD: code quality scoring + test coverage |

### New Functions

| Function | Purpose |
|----------|---------|
| `gptel-benchmark--code-quality-score` | Docstring coverage (0.0-1.0) |
| `gptel-benchmark--detect-llm-degradation` | Detect off-topic/repetition/loops |
| `gptel-auto-experiment--code-quality-score` | Integration with auto-experiment |

### Test Status

```
Isolation tests (pass individually):
- grader/*              19/19 ✓
- retry/*               32/32 ✓
- git-grep/*             3/3 ✓
- find-usages/*          2/2 ✓
- agent-loop/*          18/18 ✓
- agent-yaml/*           7/7 ✓
- nucleus-presets/*      3/3 ✓
- tool-confirm/*         5/5 ✓
- treesit/*             21/21 ✓

Full suite: 1051/1115 (33 fail due to test isolation)
Subset (grader+retry+agent-loop+tools-code): 112/117 pass
```

### Known Issue: Test Isolation

Tests pass in isolation but fail when run together. Cause: global state pollution between tests. Root causes:
1. Mock functions overwrite each other when multiple test files loaded
2. Advice persists across tests
3. `require` order affects function definitions

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

### Bug Fixes

1. `vc-git-root` → `file-directory-p .git` (batch mode compatibility)
2. Test script load path (packages/gptel*)
3. Test helper regex sync with real implementation
4. `gptel-request--transitions` var in tests
5. `USER_EMACS_DIRECTORY` env fallback

---

## λ Summary

```
λ tdd. red → green → refactor
λ detect. forbidden + missing_expected = degradation
λ fix. vc-git-root → file-directory-p (batch mode)
λ fix. test vars + env fallback
λ learn. isolation ≠ together (test order matters)
```