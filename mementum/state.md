# Mementum State

> Last session: 2026-05-11 09:55

## Current Session: 2026-05-11 Daemon Restart + Staging Worktree Fix Active

**Status:** Daemon restarted with fix (`184ae9dd`). Staging flow issue resolved. Pipeline can now continue.

**Done (This Session):**
- ✅ **Restarted copilot-auto-workflow daemon** — Now running with staging worktree stale path fix
- ✅ **Socket verified** — `copilot-auto-workflow` socket available in `/run/user/1000/emacs/`
- ✅ **Staging-verify worktree operational** — `var/elpa` seeded correctly

**Key Findings:**
- Staging verification failed previously due to missing `var/elpa` directory
- Daemon restart activates the fix from `184ae9dd` (stale path validation)
- Worktrees seeded from main repo correctly now

**Provider Status:**
- MiniMax: WORKING (quota reset at May 11 00:00+08:00)
- CF-Gateway: WORKING (fallback backend)
- moonshot: WORKING (fallback for analyzer/grader)

**Current Batch:** `2026-05-11T070228Z-8432` — 19 experiments logged

**Next Steps:**
- Monitor staging flow for new experiments
- Check if sanitize exp-3 can proceed through staging verification now

**Done (This Session):**
- ✅ **Fixed CF-Gateway "Could not parse HTTP response" errors** (`gptel-ext-backends.el`):
  - Root cause: CF-Gateway with kimi-k2.6 returns responses in `reasoning_content` field, `content` is null
  - Added advice around `gptel--parse-response` to fall back to `reasoning_content` when content is null
  - Verified with direct curl test and emacsclient gptel-request tests
- ✅ **Fixed provider blacklisting for transient errors** (`gptel-tools-agent-error.el`):
  - Root cause: `activate-provider-failover` always blacklisted backends, even for timeouts/parse errors
  - Added `skip-blacklist` parameter - only rate limits and hard quotas trigger blacklisting
  - Prevents CF-Gateway from being incorrectly blacklisted for transient failures
- ✅ **Fixed backend column accuracy** (`gptel-tools-agent-experiment-core.el`):
  - Root cause: Captured global `gptel-backend`, not the effective subagent override backend
  - Now captures override preset first, falling back to global backend
  - TSV correctly shows actual backend used (CF-Gateway, moonshot, etc.)
- ✅ **Fixed pipeline script Linux compatibility** (`scripts/run-pipeline.sh`):
  - `stat -f %m` is macOS syntax; changed to `stat -c %Y` for Linux
  - Prevents "unbound variable" error during pipeline integration verification
- ✅ **Tuned timeouts for CF-Gateway**:
  - Experiment: 350s → 500s → **800s** (CF-Gateway needs ~800s for complex multi-step)
  - Grader: 120s → **180s** (prevents grader-timeout failures)
  - Active grace: 60s (unchanged, total max ~860s)
  - Updated dynamically via emacsclient and committed to source
- ✅ **Pipeline run completed** with fixes active:
  - 7 experiments, 2 kept, 2 discarded, 1 validation-failed, 2 grader-timeout
  - Backend column correctly shows "CF-Gateway" for all experiments
  - No blacklisting issues observed

**Key Learnings:**
1. **CF-Gateway returns reasoning_content, not content** — kimi-k2.6 on CF-Gateway puts actual response in `reasoning_content` field; `content` is null. This breaks gptel's OpenAI parser which expects content.
2. **Transient errors should NOT blacklist providers** — Only rate limits and hard quotas should blacklist. Timeouts, parse errors, connection failures are transient and switching to fallback without blacklisting is correct.
3. **Backend column must capture effective backend** — The global `gptel-backend` is not the actual backend when subagent provider overrides are active. Must check override preset first.
4. **CF-Gateway needs 800s+ for complex experiments** — Simple prompts complete in 8-44s, but multi-step code analysis with tool calls takes 600-900s consistently.
5. **Dynamic timeout updates work via emacsclient** — Can update `gptel-auto-experiment-time-budget` and `my/gptel-agent-task-timeout` on running daemon without restart.
6. **Pipeline script portability matters** — macOS `stat -f %m` vs Linux `stat -c %Y` caused unbound variable errors.

**Provider Status:**
- MiniMax: EXHAUSTED (resets May 11 00:00+08:00)
- CF-Gateway: WORKING (primary backend, slow but reliable with fix)
- moonshot: WORKING (fallback for analyzer/grader)
- DashScope/DeepSeek: Available (deeper fallback chain)

**Next Steps:**
- Monitor next pipeline run with 800s timeout for CF-Gateway
- Verify no grader timeouts with 180s grader timeout
- When MiniMax quota resets, verify failover chain still works
- Consider if 800s is too long for scheduled runs (may need fewer experiments per run)

---

## Previous Session: 2026-05-10 Pipeline Completion + Timestamp Cleanup + Axis Detection

**Status:** Session complete. Pipeline run finished. Multiple infrastructure improvements deployed.

**Done (That Session):**
- ✅ **Pipeline run completed** (9 experiments, 2 kept, 7 skipped due to API pressure):
  - gptel-sandbox.el: 2 kept (hash-table-p fix + arity consolidation), 5 discarded
  - 7 targets skipped: API pressure threshold (5 rate-limit errors) reached
- ✅ **Fixed timestamp noise** in auto-generated tracked files
- ✅ **Tuned timeout for moonshot fallback**: 180s → 350s idle timeout
- ✅ **Auto-detect exploration axis** from hypothesis keywords (A-F)
- ✅ **Added inspection-thrash warning** to validation retry prompt
- ✅ **Merged 2 staging branches** with real improvements

**Key Learnings (from previous):**
1. **Timestamp noise is harmful** — Auto-generated timestamps create meaningless git diffs
2. **Git already has timestamp info** — `git log` shows when files were modified
3. **moonshot needs 350s+** — Complex code analysis takes ~350s; 180s was too aggressive
4. **Validation retry needs inspection-thrash guidance** — Agents get stuck reading without writing
5. **evaluations.jsonl should be in var/tmp/** — Auto-generated data doesn't belong in source control