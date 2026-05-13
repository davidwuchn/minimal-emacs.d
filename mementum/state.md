# Mementum State

> Last session: 2026-05-13


## Current Session: External Research Pipeline Fixes

**Status:** All syntax errors fixed, daemon restarted with clean code. External research thresholds lowered. Ready for pipeline testing.

**Done (Today):**
- **Race condition fixes** — subagent loads correctly, concurrency guard prevents overlap
- **Cons error fix** — agent-loop handles reasoning blocks `(cons 'reasoning text)`
- **Syntax fixes** — multiple paren issues in strategic.el:
  - Missing cl-block wrapper + extra parens in research-patterns
  - Extra `)` at EOF
  - `let` → `let*` in extract-research-steps (json-start variable scope)
- **External research thresholds lowered:**
  - `research-has-external-content-p`: 1000→400 chars (turn 1 = 500-700 chars)
  - `digest-research-findings`: 2000→500, 500→300 (avoids over-digesting)
- **Daemon restarted** — clean state with all fixes loaded

**Test Results:**
- Turn 1: 745 chars in 81s (MiniMax) → controller decides "continue"
- Turn 1 (retry): 526 chars in 64s → controller decides "continue"  
- Turn 2: Times out after 180s (web fetches take too long)
- Threshold tests: 600 chars → t (external), 300 chars → nil
- json-start void variable: FIXED with let*

**Pipeline Impact:**
- Before: 0-char findings → `research: unknown`
- After: 500-700 char findings → `research: external` (meets 400-char threshold)

**Commits:**
- `a7a8992e` — Δ Fix syntax errors: extra parens in research-patterns and EOF
- `dd6ebe59` — Δ Fix json-start void variable: let→let*
- `322d524e` — Δ Lower external research thresholds for multi-turn controller
- Both remotes synced

**Next Steps:**
1. Monitor next pipeline run (19:00) for `research: external` classification
2. Check findings file updated with external content
3. If turn 2 timeout is problematic, consider single-turn mode

**Pipeline Status:**
- 19:00: Next scheduled run
- Cron: `0 23,3,7,11,15,19 * * *`
