# Daemon Corruption During Provider Fallback

**Issue:** When attempting to switch from MiniMax to DashScope after quota exhaustion, daemon became corrupted.

**Symptoms:**
1. Skill content (eight-keys-grader.md) polluting daemon log files
2. "Symbol's value as variable is void: async" errors preventing workflow runs
3. Workflow stuck in `:running t` state with no experiment progress

**Attempted Fixes:**
- Killed daemon, restarted with DashScope as primary fallback
- Set `gptel-auto-workflow--rate-limited-backends` to `("MiniMax")`
- Reordered `gptel-auto-workflow-headless-subagent-fallbacks` to put DashScope first
- Cron script eventually started new run (2026-05-08T203220Z-2c48) but daemon corrupted

**Suspected Root Causes:**
1. `cl-defstruct` in `gptel-programmatic-benchmark.el` defines field named `async` - may conflict with something
2. Skill loader functions may output content to stdout instead of returning silently
3. Daemon state inconsistent after manual kill/restart cycle

**Resolution:**
- Killed corrupted daemon (PID 3870739)
- Next cron cycle (~4 hours) will auto-start fresh daemon
- Skill extraction work completed before corruption

**Lesson:** Provider switching works in theory (failover chain tested successfully), but daemon state management is fragile. Avoid manual daemon manipulation; let cron handle lifecycle.

**Date:** 2026-05-08
