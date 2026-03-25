# Mementum State

> Last session: 2026-03-25

## Session Summary: Strategic Target Selection with LLM

**Key insight: Let LLM make decisions, minimize local logic.**

### Latest Changes

| Commit | Description |
|--------|-------------|
| `678cb2c` | Tests run before push |
| `ab77594` | State update |

### New Architecture

```
Target Selection Flow:
1. Gather context (git history, file sizes, TODOs)
2. Ask analyzer LLM to decide targets
3. LLM outputs JSON with priorities and reasons
4. We execute LLM's decision (no second-guessing)
```

### Design Principles

1. **LLM decides, we execute** - Don't second-guess with local calculations
2. **Provide rich context** - Git history, file sizes, TODOs, test data
3. **Structured output** - JSON format for reliable parsing
4. **Fallback only if LLM unavailable** - Local scoring is backup, not primary

### What We Stopped Doing

| Before | After |
|--------|-------|
| Local scoring formula | LLM analyzes and decides |
| Weight-based calculation | LLM judgment |
| Combine local + LLM | Pure LLM decision |
| Multi-step validation | Single LLM call |

### New Functions

```elisp
(gptel-auto-workflow--analyze-for-target-selection callback)
;; Asks LLM to pick 3 targets based on git, size, TODOs

(gptel-auto-workflow-select-targets-with-analyzer callback)
;; Entry point: LLM decides or fallback

(gptel-auto-workflow--parse-analyzer-targets response)
;; Parse JSON: {"targets": [{"file": "...", "priority": 1, "reason": "..."}]}
```

### Analyzer Prompt Structure

```
Context provided:
- Available files in lisp/modules/
- Recent git history (30 commits)
- Files by size (lines)
- Known issues (TODOs, FIXMEs)

LLM outputs:
{
  "targets": [
    {"file": "lisp/modules/xxx.el", "priority": 1, "reason": "...", "suggested_focus": "..."}
  ],
  "strategy": "Overall strategy"
}
```

### Safety Net

1. ✓ Tests run before any push
2. ✓ Nucleus validation before commit
3. ✓ Grader validates output quality
4. ✓ Comparator decides keep/discard
5. ✓ Only optimize/* branches pushed

### Production Status

| Component | Status |
|-----------|--------|
| Target selection | ✓ LLM decides |
| Tests before push | ✓ |
| All tests | ✓ 52/52 |
| Cron | ✓ 2 AM daily |

---

## λ Summary

```
λ learn. LLM makes better decisions than local formulas
λ simplify. One LLM call replaces complex scoring
λ trust. Let analyzer decide, we execute
λ context. Rich context = better LLM decisions
```