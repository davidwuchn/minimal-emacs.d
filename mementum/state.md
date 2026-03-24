# Mementum State

> Last session: 2026-03-24

## Session Complete ✓

**20 commits** | **3 workarounds fixed** | **22+ code improvements**

### Major Achievement: Streaming Fixed

| Component | Before | After |
|-----------|--------|-------|
| DashScope API | `:stream nil` | `:stream t` ✓ |
| Subagent calls | `:stream nil` | `:stream t` ✓ |
| Executor tools | 4 (lite) | 27 (full) viable |

### Fix Chain

```
630fbd4: "disable streaming" (workaround)
    ↓ documented root cause: SSE format differs
6fb1a0d: Custom gptel-dashscope struct
54f5c37: Fixed parser (skip-chars-forward)
8591cfe: Fixed model format (plain symbols)
31cc8e7: Added protocol parameter
d60312c: Fixed URL nil issue
fcda2ae: Enabled subagent streaming
    → STREAMING WORKS!
```

### Commits Summary

| Category | Count |
|----------|-------|
| Streaming fixes | 8 |
| Code quality | 3 |
| Knowledge/docs | 4 |
| State updates | 5 |

### Knowledge Created

| Page | Purpose |
|------|---------|
| dashscope-backend.md | Configuration & fixes |
| ab-testing.md | Framework usage |
| git-history-improvement-strategy.md | Updated with results |

### Pattern Validated ✓

**Git History → Workarounds → Fixes**

This pattern successfully resolved:
1. DashScope streaming (630fbd4 → d60312c)
2. Subagent streaming (6e09a87 → fcda2ae)

Use this pattern for future workarounds.

### Next Session

1. Run A/B test comparing executors
2. Monitor streaming reliability
3. Continue auto-evolution with full executor