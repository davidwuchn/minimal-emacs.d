# Mementum State

> Last session: 2026-03-24

## Major Achievement ✓

**DashScope Streaming: FIXED**

| Metric | Before | After |
|--------|--------|-------|
| Streaming | Disabled (`:stream nil`) | Working (`:stream t`) |
| Tools available | 4 (lite-executor) | 27 (executor) |
| API calls | 100-200s timeout | 2-30s reliable |
| UX | Batch output | Incremental streaming |

### Fix Chain

```
630fbd4 → "fix DashScope: disable streaming" (workaround)
    ↓
6fb1a0d → Custom gptel-dashscope struct
54f5c37 → Fixed parser: skip-chars-forward
8591cfe → Fixed model format: plain symbols
31cc8e7 → Added protocol parameter
d60312c → Fixed URL nil issue
    ↓
STREAMING WORKS!
```

### Knowledge Created

| Page | Content |
|------|---------|
| `dashscope-backend.md` | Configuration, fixes, testing |
| `ab-testing.md` | Framework usage, decision criteria |
| `git-history-improvement-strategy.md` | Updated with fix results |

## Session Stats

| Metric | Value |
|--------|-------|
| Commits | 12 |
| Files fixed | 8 |
| Issues resolved | 22 |
| Knowledge pages | 3 |
| Memories | 2 |

## Remaining Work

1. Run A/B test comparing executors
2. Verify streaming reliability over time
3. One byte-compile warning: `result` free variable in `gptel-workflow-benchmark.el:736`

## Pattern Validated

**Git History → Workarounds → Fixes**

```
git log --grep="workaround\|fix\|bypass"
  → read commit message for root cause
  → implement proper fix
  → test and verify
  → commit with reference
```

This pattern works. Use it for future workarounds.