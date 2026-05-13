# Mementum State

> Last session: 2026-05-13


## Current Session: AutoTTS Implementation Sprint + Race Condition Fixes

**Status:** External research thresholds lowered to match multi-turn controller output. Turn 1 produces 500-700 chars, now counts as external research.

**Done (Today):**
- **Race condition fixes** — subagent loads correctly, concurrency guard prevents overlap
- **Cons error fix** — agent-loop handles reasoning blocks `(cons 'reasoning text)`
- **Syntax fix** — missing cl-block wrapper + paren in strategic.el
- **json-start error** — fixed void variable in `extract-research-steps`
- **External research thresholds lowered:**
  - `research-has-external-content-p`: 1000→400 chars (turn 1 = 500-700 chars)
  - `digest-research-findings`: 2000→500, 500→300 (avoids over-digesting)
  - Pipeline Step 4 will now classify turn 1 results as external

**Test Results:**
- Turn 1: 745 chars in 81s (MiniMax) → controller decides "continue"
- Turn 1 (retry): 526 chars in 64s → controller decides "continue"
- Turn 2: Times out after 180s (web fetches take too long)
- Webfetch files: 22KB-84KB real content fetched successfully
- Threshold tests: 600 chars → t (external), 300 chars → nil

**Pipeline Impact:**
- Before: 0-char findings → `research: unknown`
- After: 500-700 char findings → `research: external` (meets 400-char threshold)

**Commits:**
- `322d524e` — Δ Lower external research thresholds for multi-turn controller
- Both remotes synced

**Next Steps:**
1. Monitor 15:00 pipeline run for `research: external` classification
2. If turn 2 timeout is problematic, consider single-turn mode or longer timeout
3. Verify findings file updated with external content markers

**Pipeline Status:**
- 15:00: Next scheduled run (will use lowered thresholds + multi-turn controller)
- Cron: `0 23,3,7,11,15,19 * * *`
