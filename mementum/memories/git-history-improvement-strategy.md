# Git History as Improvement Source

## Discovery
Git history contains workarounds that could be properly fixed. Each workaround is an opportunity for improvement.

## Pattern
```
workaround commit → "fix X by doing Y" → root cause documented but not fixed
```

## Workarounds Fixed ✓

| Commit | Workaround | Fix | Result |
|--------|------------|-----|--------|
| `630fbd4` | Disable DashScope streaming | `d60312c` - Custom gptel-dashscope backend | ✅ Streaming works! |
| `a7b0931` | lite-executor (4 tools) | Can now use full executor | Ready for A/B test |

## Fix Chain for DashScope

```
630fbd4: "fix DashScope: disable streaming"
   ↓ commit message documents root cause
6fb1a0d: Create gptel-dashscope struct
   ↓ extends gptel-openai with custom parser
54f5c37: Fix parser regex issues
   ↓ use skip-chars-forward not match-end
8591cfe: Fix model format (plain symbols)
   ↓ gptel--sanitize-model expects symbols
31cc8e7: Add protocol parameter
   ↓ URL construction needs protocol
d60312c: Fix URL nil issue
   ↓ setf gptel-backend-url after creation
   → STREAMING WORKS!
```

## Remaining Workarounds

| Commit | Workaround | Status |
|--------|------------|--------|
| `a7b0931` | lite-executor | A/B test pending |

## Process
1. Extract workarounds from git log: `git log --grep="workaround\|fix\|bypass"`
2. Identify root cause in commit message
3. Design proper fix
4. Test thoroughly
5. Commit with reference to original workaround
6. Remove workaround if no longer needed

---
*Updated: 2026-03-24*