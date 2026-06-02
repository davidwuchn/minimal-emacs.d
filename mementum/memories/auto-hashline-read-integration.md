# Auto-Hashline Read Integration

## What
Made Read tool automatically return hashline format when executor agent is running.

## Problem
Executor agents had to explicitly pass `hashline=true` on every Read call. Many forgot, causing edit failures.

## Solution
Dynamic variable `gptel-tools-read-hashline-default`:
- Set to `t` when executor subagent starts
- Read tool checks variable, auto-enables hashline format
- Cleared after subagent completes

## Data Flow
```
Executor subagent starts
    │
    ├── gptel-tools-read-hashline-default = t
    │
    ▼
Read tool called (no hashline param)
    │
    ├── checks gptel-tools-read-hashline-default
    ├── if t → returns hashline format
    └── if nil → returns plain text
    │
    ▼
Edit tool uses hashline format
    │
    ▼
Success → gptel-tools-edit--mode-used = 'hashline
```

## Files Changed
- `lisp/modules/gptel-tools-edit.el` — Added dynamic variable
- `lisp/modules/gptel-tools.el` — Read tool checks variable
- `lisp/modules/gptel-benchmark-subagent.el` — Executor sets variable

## Verification
- Hashline tests still pass (15/15)
- No breaking changes to existing Read calls
- Only affects executor subagent context

## Next Steps
1. Monitor edit-mode distribution in experiments
2. If hashline rate < 80%, investigate why agents still use string mode
3. Consider making hashline the universal default (not just executor)

## Related
- `mementum/memories/hashline-edit-tool-implementation.md`
- `mementum/memories/harness-problem-edit-tool-critical.md`
- `mementum/memories/edit-mode-tracking-integration.md`
