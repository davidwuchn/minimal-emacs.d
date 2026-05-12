# Mementum State

> Last session: 2026-05-12 10:12

## Current Session: 2026-05-12 Executor Retry-First Logic

**Status:** Executor now retries MiniMax 5 times before advancing to fallback (same pattern as aux subagents). Pipeline 11:00 will test the new logic.

**Done:**
- Fixed executor failover to handle timeouts (curl 28) not just rate limits
- Added `provider-attempts` tracking to executor retry loop
- Increased `max-per-provider-attempts` from 2 to 5 for MiniMax subscription
- Increased `max-retries` from 2 to 5
- Timeout: advance provider WITHOUT blacklisting (transient)
- Rate limit/hard quota: advance AND blacklist permanently
- Synced with remote, resolved merge conflicts

**Key Files Changed:**
- `lisp/modules/gptel-tools-agent-error.el`: Added `should-advance` logic, changed `when raw-error` to `when should-advance`
- `lisp/modules/gptel-tools-agent-prompt-build.el`: Increased retry limits

**Pipeline Status:**
- 07:00: Running (auto-workflow waiting)
- 03:00: Completed (8 experiments, all timeout on MiniMax)
- Next: 11:00, 15:00, 19:00, 23:00

**Next Steps:**
- Monitor 11:00 pipeline for retry-first behavior
- Verify MiniMax gets 5 attempts before advancing to moonshot
- Check if experiments succeed with new retry logic