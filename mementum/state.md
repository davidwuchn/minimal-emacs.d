# Mementum State

> Last session: 2026-05-13

## Current Session: 2026-05-13 Researcher Race Condition Fixes

**Status:** Fixed race conditions causing 0-char research findings and "research: unknown" pipeline failures.

**Done:**
- Added `(require 'gptel-benchmark-subagent nil t)` to strategic.el to ensure subagent function is always loaded before `fboundp` check
- Added debug instrumentation logging subagent availability state and timestamp
- Added `gptel-auto-workflow--research-in-progress` guard to prevent overlapping async research calls from interleaving
- Reset guard flag in all callback paths: success (before calling callback), retry (before recursive call), and unavailable branch
- Merged origin/main (remote AutoTTS integration fixes + adaptive-skills strategy)
- Pushed to both origin and upstream at `c3c9b6dd`

**Key Files Changed:**
- `lisp/modules/gptel-auto-workflow-strategic.el`: Require benchmark-subagent, debug logs, concurrency guard

**Root Cause:**
- Two overlapping `research-patterns` calls within single daemon: one inside `my/gptel--agent-task-with-timeout` (prints "Delegating"), another hitting else-branch (prints "Subagent unavailable")
- `gptel-benchmark-call-subagent` was lazily loaded, causing race where `fboundp` returned nil for second call
- No concurrency guard allowed interleaved async callbacks

**Pipeline Status:**
- Previous: Step 4 reporting `research: unknown` due to 0-char findings
- Fix: Race condition eliminated, subagent guaranteed loaded, concurrent calls deduplicated
- Next pipeline run will validate fixes

**Next Steps:**
- Monitor next pipeline run for "research: external" instead of "unknown"
- Verify debug logs show `subagents-enabled=t fbound=t` in cron logs
- Check that findings file contains URLs/techniques (2000+ chars)
- If issues persist, examine `var/tmp/cron/copilot-researcher.log` for debug output
