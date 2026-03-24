# Mementum State

> Last session: 2026-03-24

## Recent Learning 🔁

**Git History as Improvement Source**

Workarounds in git history are opportunities for proper fixes:

```
git log --grep="workaround\|fix\|bypass" → identify root cause → A/B test fix
```

### Current Workarounds to Fix

| Commit | Workaround | Root Cause | Status |
|--------|------------|------------|--------|
| `630fbd4` | Disable DashScope streaming | SSE format differs from OpenAI | Needs fix |
| `a7b0931` | lite-executor (4 tools) | 27 tools too slow without streaming | Needs A/B test |

### A/B Test Framework Added

```elisp
(gptel-ab-test-run "prompt")  ; Compare lite-executor vs executor
```

**Limitation**: Async callbacks don't work via `emacsclient --eval`. Run interactively in Emacs.

## Built ✓

**Systematic Code Review**

```
scan repo → categorize issues → prioritize → fix
```

| Category | Fixed |
|----------|-------|
| Duplicate functions | 2 |
| Unused variables | 7 |
| Docstring width >80 | 8 |
| Wrong quote usage | 4 |
| Free variable refs | 1 |

### Quality Scoring Fixed

Now correctly counts only real TODOs/defuns, not patterns in strings.

## Commits This Session

| Commit | Description |
|--------|-------------|
| `5ff621d` | Δ fix code quality issues |
| `cb539f4` | 💡 systematic-code-review learning |
| `1f5583a` | Δ fix quality scoring |
| `4d7676a` | ⚡ add A/B test framework |
| `1d2ebaa` | Δ fix A/B test: use agent-type |

## Next Steps

1. Fix DashScope SSE parsing to re-enable streaming
2. Run A/B test interactively to compare executors
3. Consider: streaming + executor vs no-stream + lite-executor