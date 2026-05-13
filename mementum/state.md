# Mementum State

> Last session: 2026-05-13


## Current Session: AutoTTS Implementation Sprint + Race Condition Fixes

**Status:** External research is now working! Subagent performs real web searches and page fetches. Multi-turn controller active. Remaining issue: Turn 2 hits 180s timeout, and turn 1 results (526-745 chars) may not contain URLs needed for pipeline to classify as "external".

**Verified Working:**
- ✅ Race conditions fixed (subagent loads, concurrency guard works)
- ✅ Cons error fixed (agent-loop handles reasoning blocks)
- ✅ Syntax error fixed (missing paren + cl-block wrapper)
- ✅ External research IS happening (web searches + page fetches)
- ✅ Multi-turn controller working (turn 1 completes, decides to continue)
- ✅ json-start error fixed (function rebound in daemon)

**Test Results:**
- Turn 1: 745 chars in 81s, controller decides "continue"
- Turn 1 (second run): 526 chars in 64s, controller decides "continue"
- Turn 2: Times out after 180s (web fetches take too long)
- Webfetch temp files created: 22KB-84KB of real content (LLM prompt injection research)

**Pipeline Impact:**
- `research-has-external-content-p` requires either:
  - Length > 1000 chars, OR
  - Contains `https?://`, OR
  - Contains `## .*Technique` or `Source type:`
- Turn 1 results (526-745 chars) may NOT meet these criteria
- Pipeline may still report `research: unknown` or `failed`

**Key Files Changed:**
- `lisp/modules/gptel-auto-workflow-strategic.el`: Multi-turn controller + race fixes
- `lisp/modules/gptel-agent-loop.el`: Reasoning block handler
- `lisp/modules/gptel-auto-workflow-research-benchmark.el`: Convergence + offline benchmark

**Next Steps:**
1. **Lower threshold** for external content detection (526-745 chars should count)
2. **Increase timeout** for turn 2 (180s → 300s) or reduce to single-turn mode
3. **Ensure researcher output** includes URLs or technique markers
4. Monitor 15:00 pipeline run for actual classification

**Pipeline Status:**
- 15:00: Next scheduled run (will use multi-turn controller + fixes)
- Cron: `0 23,3,7,11,15,19 * * *`

---

*AutoTTS integration: External research functional, timeout tuning needed.*
*Both remotes synced at 2b3878fb.*
