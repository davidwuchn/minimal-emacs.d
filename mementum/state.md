# Mementum State

> Last session: 2026-05-13


## Current Session: External Research Pipeline Fixes

**Status:** Remote fixes pulled, daemons killed, ready for 19:00 pipeline run. All syntax errors fixed.

**Done (Today):**
- **Race condition fixes** — subagent loads correctly, concurrency guard prevents overlap
- **Cons error fix** — agent-loop handles reasoning blocks `(cons 'reasoning text)`
- **Syntax fixes** — multiple paren issues in strategic.el fixed by remote:
  - Missing cl-block wrapper + extra parens in research-patterns
  - Extra `)` at EOF
  - `let` → `let*` in extract-research-steps (json-start variable scope)
- **External research thresholds lowered:**
  - `research-has-external-content-p`: 1000→400 chars (turn 1 = 500-700 chars)
  - `digest-research-findings`: 2000→500, 500→300 (avoids over-digesting)
- **Remote fixes pulled** — `2f8efd15` integrates syntax fixes + local paren corrections

**Test Results:**
- Manual research run: 4152 chars in 130s (MiniMax) — excellent result!
- Turn 1: 745 chars in 81s → controller decides "continue"
- Turn 1 (retry): 526 chars in 64s → controller decides "continue"  
- Turn 2: Times out after 180s (web fetches take too long)
- Threshold tests: 600 chars → t (external), 300 chars → nil
- Callback error: "Wrong type argument: stringp, 4152" — needs investigation

**Pipeline Impact:**
- Before: 0-char findings → `research: unknown`
- After: 500-700 char findings → `research: external` (meets 400-char threshold)

**Commits:**
- `2f8efd15` — Auto-update skills from daemon (remote merge)
- `09b28fb6` — ◈ Update state: syntax fixes complete, daemon restarted
- Both remotes synced

**Next Steps:**
1. **Monitor 19:00 pipeline run** for `research: external` classification
2. Check findings file updated with external content
3. Investigate callback error if it persists
4. If turn 2 timeout is problematic, consider single-turn mode

**Pipeline Status:**
- 19:00: Next scheduled run (in ~15 minutes)
- Daemons killed — cron will start fresh instances
- Cron: `0 23,3,7,11,15,19 * * *`
