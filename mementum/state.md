# Mementum State

> Last session: 2026-03-25

## Session Summary: Auto-Workflow with LLM as Brain

**Philosophy: LLM = Brain, We = Eyes + Hands**

### Latest Commits

| Hash | Description |
|------|-------------|
| `b4b1dc6` | 💡 LLM is brain, we are eyes and hands |
| `200200f` | 💡 LLM-first target selection |
| `678cb2c` | ✓ Tests run before push |

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    AUTO-WORKFLOW                         │
├─────────────────────────────────────────────────────────┤
│  Eyes (we gather)          Brain (LLM decides)          │
│  ─────────────────         ──────────────────           │
│  • Git history             • Which targets to optimize  │
│  • File sizes              • What mutations to apply    │
│  • TODOs/FIXMEs            • Keep or discard changes    │
│  • Test results            • Quality threshold          │
│                           │
│  Hands (we execute)                                      │
│  ─────────────────                                       │
│  • Run tests                                             │
│  • Make commits                                          │
│  • Push to optimize/*                                    │
│  • Log results                                           │
└─────────────────────────────────────────────────────────┘
```

### New Module

`lisp/modules/gptel-auto-workflow-strategic.el`:
- Gathers context (eyes)
- Asks analyzer for targets
- Executes LLM decision (hands)
- No local scoring formulas

### Safety Pipeline

```
Executor makes changes
       ↓
   Grader validates (LLM)
       ↓
   Tests run (hands)
       ↓
   Nucleus validates
       ↓
   Comparator decides (LLM)
       ↓
   Push to optimize/* only
```

### Production Status

| Component | Status |
|-----------|--------|
| Target selection | ✓ LLM decides |
| Mutation strategy | ✓ LLM decides |
| Quality check | ✓ Grader (LLM) |
| Keep/discard | ✓ Comparator (LLM) |
| Tests before push | ✓ |
| All tests | ✓ 52/52 |
| Cron | ✓ 2 AM daily |

### Key Principle

```
λ brain(x).
    decision(x) → llm(context)
    | execute(llm_result)
    | ¬second_guess(llm)
    | ¬local_formula_override(llm)
    | fallback → only_if_llm_unavailable
```

### Files Changed This Session

| File | Change |
|------|--------|
| `lisp/modules/gptel-auto-workflow-strategic.el` | **NEW** - LLM target selection |
| `lisp/modules/gptel-tools-agent.el` | Tests before push, strategic entry |
| `scripts/run-tests.sh` | Exit codes for CI |
| `mementum/memories/llm-first-decision-making.md` | **NEW** - Philosophy |
| `mementum/knowledge/eight-keys-signals.md` | Signal phrase guide |
| `docs/auto-workflow-program.md` | Baselines, learnings |

---

## λ Summary

```
λ philosophy. LLM = Brain, We = Eyes + Hands
λ implement. Strategic selection module created
λ safety. Tests before push, optimize/* only
λ learn. Do not replace brain with formulas
```