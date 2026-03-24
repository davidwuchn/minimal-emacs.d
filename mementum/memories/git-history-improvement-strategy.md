# Git History as Improvement Source

## Discovery
Git history contains workarounds that could be properly fixed. Each workaround is an opportunity for improvement.

## Pattern
```
workaround commit → "fix X by doing Y" → root cause documented but not fixed
```

## Current Workarounds

| Commit | Workaround | Root Cause | Potential Fix |
|--------|------------|------------|---------------|
| `630fbd4` | Disable DashScope streaming | SSE format differs from OpenAI | Custom SSE parser for DashScope |
| `a7b0931` | lite-executor (4 tools) | 27 tools too slow without streaming | Fix SSE → re-enable streaming → use full executor |
| `5f5b90d` | Explicit `:stream nil` in preset | Same SSE issue | Same as above |

## A/B Test Strategy

| Variant | Config | Hypothesis |
|---------|--------|------------|
| A (current) | lite-executor, no streaming | Fast but limited tools |
| B | executor, no streaming | More tools, same reliability |
| C (target) | executor, streaming | Best UX, incremental output |

## Process
1. Extract workarounds from git log: `git log --grep="workaround\|fix\|bypass"`
2. Identify root cause in commit message
3. Design proper fix
4. A/B test to compare
5. Keep winner, remove workaround

## Decision Criteria
- Benchmark scores (completion, efficiency)
- Reliability (no HTTP errors)
- UX (streaming vs batch)

---
*Learned: 2026-03-24*