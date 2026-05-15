# Mementum State

> Last session: 2026-05-15

## Current Session: Pipeline Artifact Generator Cleanup

**Status:** Fixed generator defects discovered after the aborted E2E pipeline run and targeted-verified the relevant paths.

**Completed:**
- Confirmed the auto-workflow daemon is no longer running; cached `*Messages*` showed the abort happened during analyzer fallback/timeout.
- Rechecked `gptel-auto-experiment--shared-retryable-error-patterns` in the current source: `caar` and `cadr` now return strings, so the cached `wrong-type-argument stringp` was from the pre-sync daemon code path already corrected by incoming `f3dba0d2` changes.
- Fixed `gptel-auto-workflow--merge-trace-sources-into-data` to write one canonical string key, `"sources"`, and remove legacy keyword `:sources` before JSON encoding.
- Fixed `gptel-auto-workflow--synthesize-research-knowledge` to stop appending a blank line at EOF.
- Cleaned current generated artifacts enough for whitespace/JSON validation: duplicate `"sources"` removed from `source-effectiveness.json`; generated research insight EOF whitespace removed.
- Added regressions for duplicate `sources` JSON keys and blank-line-at-EOF research knowledge synthesis.
- Updated stale `gptel-auto-workflow--research-patterns` docstring: it no longer claims research is stored in `FINDINGS.md`; it now describes analyzer selection and project research cache usage.

**Verification:**
- `tests/test-gptel-auto-workflow-research-benchmark-regressions.el`: 14/14 passed.
- `tests/test-gptel-auto-workflow-evolution-regressions.el`: 3/3 passed.
- `tests/test-gptel-auto-workflow-strategic-regressions.el`: 17/17 passed after the docstring cleanup.
- Batch retry-pattern accessor check passed for `caar`/`cadr`, `is-retryable-error-p`, and `provider-pressure-error-p`.
- JSON parse check passed for `source-effectiveness.json`, `strategy-guidance.json`, and `topic-performance.json`.
- `git diff --check` passed after the docstring cleanup.

**Remaining:**
- Worktree still has uncommitted code/test fixes plus generated artifact churn from the aborted pipeline run.
- Local `main` is still ahead of `upstream/main` by 9 commits; `origin/main` was already at `f3dba0d2`.
- Full E2E pipeline was not rerun after this cleanup.

**Dirty files after cleanup:**
- `assistant/skills/evolution-patterns/SKILL.md` (generated churn)
- `assistant/skills/researcher-prompt/data/source-effectiveness.json` (generated stats, duplicate key fixed)
- `assistant/skills/researcher-prompt/data/strategy-guidance.json` (generated churn)
- `assistant/skills/researcher-prompt/data/topic-performance.json` (generated churn)
- `lisp/modules/gptel-auto-workflow-evolution.el` (generator EOF fix)
- `lisp/modules/gptel-auto-workflow-research-benchmark.el` (canonical `sources` key fix)
- `lisp/modules/gptel-auto-workflow-strategic.el` (stale docstring fix)
- `mementum/knowledge/research-insights-deep-external.md` (generated stats update)
- `tests/test-gptel-auto-workflow-evolution-regressions.el` (new EOF regression)
- `tests/test-gptel-auto-workflow-research-benchmark-regressions.el` (new JSON key regression)

## Current Session: Pipeline Post-Workflow Evolution Fix

**Status:** Implemented and targeted-verified fixes for E2E issues discovered by the full pipeline run.

**Completed:**
- Added a reusable `run_self_evolution` helper in `scripts/run-pipeline.sh`.
- Kept pre-workflow evolution for research digestion and added post-workflow evolution after a completed auto-workflow, so same-run `results.tsv` data can feed skills/controller evolution immediately.
- Exposed controller config values to agent-generated rule expressions in both runtime and offline validation/evaluation paths: priorities, thresholds, token budget, max turns, beta, and related controller fields.
- Updated the controller design prompt to list those supported signals.
- Added regressions for controller rules that reference config-derived signals.

**Verification:**
- `bash -n scripts/run-pipeline.sh` passed.
- `git diff --check` passed.
- `tests/test-gptel-auto-workflow-research-benchmark-regressions.el`: 13/13 passed.
- `tests/test-gptel-auto-workflow-strategic-regressions.el`: 17/17 passed.
- `tests/test-gptel-auto-workflow-evolution-regressions.el`: 2/2 passed.
- Byte-compile of `strategic-daemon-functions.el` and `gptel-auto-workflow-research-benchmark.el` passed with existing warnings only.

**Remaining:**
- Changes are not committed yet.
- Generated skill/stat churn and generated strategy/research insight files from the E2E run remain uncommitted by policy unless explicitly wanted.
- A full non-smoke pipeline rerun was not attempted because it can take hours.

## Current Session: Origin Merge + Pipeline Verification

**Status:** Merge `b4670f5` pushed to `origin/main` and `upstream/main`; follow-up pipeline hardening implemented and smoke-verified.

**Completed:**
- Resolved and committed the `origin/main` merge (`b4670f5 Merge remote-tracking branch 'origin/main'`), then pushed it to both remotes.
- Verified targeted suites after the merge: research benchmark, standalone research, project regressions, strategic regressions, and whitespace checks.
- Ran `scripts/run-pipeline.sh`; found follow-up issues in self-evolution/pipeline verification.
- Fixed controller design held-out validation binding (`let*` for `test-result`) and added regression coverage.
- Fixed self-evolution insufficient-data skip to return a textual skip reason instead of bare `nil`.
- Fixed pipeline/cron evolution timeout mismatch by passing `MAX_WAIT_EVOLUTION` through `AUTO_WORKFLOW_ACTION_TIMEOUT`.
- Fixed `evolution-scores.json` legacy alist/plist handling and required `json` explicitly.

**Verification:**
- `tests/test-gptel-auto-workflow-evolution-regressions.el`: 2/2 passed.
- `tests/test-gptel-auto-workflow-research-benchmark-regressions.el`: 11/11 passed.
- `tests/test-standalone-research.el`: 3/3 passed.
- `tests/test-gptel-auto-workflow-projects-regressions.el`: 13 expected, 2 skipped.
- `tests/test-gptel-auto-workflow-strategic-regressions.el`: 14/14 passed.
- `bash -n scripts/run-auto-workflow-cron.sh` and `bash -n scripts/run-pipeline.sh` passed.
- `PIPELINE_SMOKE_ONLY=yes scripts/run-pipeline.sh` now reaches self-evolution and reports `Self-evolution skipped (insufficient new data)` cleanly.

**Remaining:**
- Generated skill/stat churn from smoke/full pipeline runs remains uncommitted by policy unless explicitly wanted.
- Full non-smoke `scripts/run-pipeline.sh` auto-workflow batch was not rerun after the follow-up fixes because it can take hours.

**Remote Sync Fix (2026-05-15):**
- Fast-forwarded local `main` to `origin/main` commit `2fb9f0e0`.
- Review found two regressions: stray top-level `updated`/`results` references in `gptel-auto-workflow--bridge-trace-outcomes`, and controller rules losing signal bindings under lexical `eval`.
- Fixed trace bridge paren/tail issue, restored rule evaluation with explicit signal alist, guarded missing confidence estimator, and added strategic regressions for rule signal visibility.
- Verification: research benchmark regressions 11/11, strategic regressions 16/16, standalone research 3/3, project regressions 13 expected/2 skipped, evolution regressions 2/2; byte-compile of touched modules passed with warnings only.

## Current Session: AutoTTS integration + research daemon fix

**Status:** Deep integration pass complete; standalone research remains active; auto-workflow queue nil-hash crash fixed and live run has reached experiments.

**Auto-Workflow Queue Fix (2026-05-14):**
- Root cause of `[auto-workflow] Job failed: (wrong-type-argument hash-table-p nil)` was `gptel-auto-workflow--normalized-projects` calling `gethash` on `gptel-auto-workflow--normalized-projects-hash` before shared buffer/hash tables were initialized.
- Fixed by calling `gptel-auto-workflow--ensure-buffer-tables` at the start of `gptel-auto-workflow--normalized-projects`.
- Added regression `regression/auto-workflow-projects/normalized-projects-recovers-nil-hash`.
- Verification: `check-parens` passed; focused regression passed; live `copilot-auto-workflow` run moved from immediate error to `:phase "running"`, selected 5 targets, and started experiment 1.
- Remaining live-run behavior is experiment-level executor retry/inspection-thrash, not the original daemon queue crash.

**Deep Integration Pass (2026-05-14):**
- Unified runtime controller loading: `gptel-auto-workflow-strategic.el` now loads `strategic-daemon-functions.el`, replay cache, and benchmark module so cron and interactive paths use the same AutoTTS controller.
- Controller config merge fixed: beta schedule, evolved `researcher-controller.json`, statistical model, and `researcher-feedback.sexp` now combine into one normalized plist with `:stop-threshold`, `:token-budget`, `:beta`, and source priorities.
- Replay cache made production-aware: `gptel-auto-workflow-research-cache.el` now indexes existing `var/tmp/research-traces/*.json`, detects topics from outcomes/strategy/prompt, loads trace files by ID, and replays with stored EMA/turn state.
- Research trace schema enriched: new traces now save raw `:findings`/`:output`, `:ema-conf`, `:ema-delta`, `:turn-count`, and `:trace-log` for offline replay.
- Source scheduling now reaches the live researcher prompt via `gptel-auto-workflow--build-research-prompt`, not just a side skill file.
- Researcher prompt now requires JSON metadata (`strategy_used`, `sources_checked`, `topics_covered`, `confidence_final`, `insights_count`, `tokens_estimate`) so future traces are replay-complete.
- Outcome synthesis now uses actual downstream kept/discarded outcomes before falling back to output length.
- Fixed `:json-false` truthiness bug: JSON false is no longer counted as kept in trace success, source effectiveness, or research batch summaries.
- Fixed reward bridge write bug: `gptel-auto-workflow--update-trace-outcomes` now uses `erase-buffer` instead of undefined `erase`.
- Self-evolution cross-layer hook fixed: `gptel-auto-workflow--evolve-all-skills` now passes the loaded controller config to `gptel-auto-workflow--update-skill-with-controller`.

**Verification (Deep Pass):**
- Full AutoTTS modules loaded in batch.
- Full strategic stack loaded with `strategic-daemon-functions`, replay cache, and benchmark module active.
- Byte-compiled changed AutoTTS/evolution modules; only existing cross-module/free-variable warnings remain.
- Replay index verified: 15 traces indexed across `nil-safety`, `performance`, `general`, `error-handling`, and `async`.
- Offline eval verified: `nil-safety` replay evaluated 4 cached traces with 0 LLM calls.
- Trace synthesis verified: 15 traces loaded, 12 with known downstream outcomes, 10 successful after fixing JSON false handling.

**Research Daemon Maphash Fix:**
**Root Cause:** `load-file` corrupts complex defuns with nested lambdas in the daemon context. The Elisp reader misparses `maphash` lambda forms, pulling the hash-table argument into the lambda body — causing `(wrong-number-of-arguments maphash 1)` or `maphash 3` errors.

**Failed approaches:**
- `eval-buffer` in temp buffer with `lexical-binding t` — reader still corrupts
- `read` + `eval` individual forms — same reader issue
- `after-load-functions` with `eval` of quoted forms — the quoted form is also read by the corrupt reader
- `defalias` in post-init.el — reader corrupts the lambda form

**Verification:**
- ✅ Phase 5: Adaptive prompts tested (default/CONTINUE/BRANCH)
- ✅ Phase 5: Byte-compile clean, no new warnings
- ✅ Phase 5: Committed and pushed (`db7cfae8`)
- ✅ Statistical learning produces valid config (6 traces, 4 kept, 67% base rate)
- ✅ Controller switches to statistical method when data available
- ✅ Probabilities calculated: P(kept|good) ≈ 0.99, P(kept|bad) ≈ 0.01
- ✅ Falls back to heuristic when insufficient data
- ✅ All syntax verified via `forward-sexp`
- ✅ **Gap fixes committed** (`8b524f79`): 6 critical issues resolved
  - Function collision fixed
  - Statistical model loading implemented
  - Controller decision logged in TSV
  - EMA-outcome correlation tracked
  - Source table auto-populated from traces
  - Feedback loop reads researcher-feedback.sexp

**Working fix (`d418760d`):**
- Created `lisp/modules/standalone-research.el` — bypasses ALL strategic.el functions
  - Loads `SKILL.md` → calls `gptel-benchmark-call-subagent` → saves findings
  - No `maphash`, no complex lambdas — survives `load-file` intact
- Modified `post-init.el` (when `MINIMAL_EMACS_WORKFLOW_DAEMON=1`):
  - Loads `standalone-research.el`
  - `defalias` `gptel-auto-workflow-run-research` → `slr-run-research`
  - `after-load-functions` hook re-applies alias after strategic file reloads by cron
- Verified: research findings → 2191 bytes (was 86 bytes header-only)
- Pushed to origin + upstream

**Pattern discovered:** `load-file` corrupts ANY form containing `maphash` with a nested `lambda` that has closure variables. The `topics` (or similar) argument to `maphash` gets parsed into the lambda body instead of after it. This is a persistent Emacs Lisp reader bug in the daemon context.

**Daemon status:**
- ✅ `copilot-auto-workflow` — running (PID 96202, since yesterday)
- ✅ `copilot-researcher` — running (PID 60750, with standalone override active)
- Findings file: `/Users/davidwu/.emacs.d/var/tmp/research-findings.md` — 2191 bytes

**Next Steps (Completed):**
1. ✅ **Fix function collision** — renamed `synthesize-research-knowledge` → `synthesize-research-knowledge-from-traces` in `research-benchmark.el`
2. ✅ **Implement `load-statistical-model`** — loads from `researcher-controller.json`
3. ✅ **Add controller_decision column** to `results.tsv`
4. ✅ **Add EMA-outcome correlation** to self-evolution synthesis
5. ✅ **Populate source table from traces** on startup
6. ✅ **Read researcher-feedback.sexp** into controller config (beta adjustment)

**Next Steps:**
1. **Monitor pipeline** — verify adaptive prompts appear in research logs (requires pipeline run)
2. **Measure improvement** — compare research effectiveness before vs after Phase 5 (requires data collection)
3. ✅ **Fix heuristic BRANCH** — resolved (mutually exclusive conditions removed in `strategic-daemon-functions.el`)
4. **Monitor cron** — verify standalone research continues to populate findings every 4h
5. **Simplify daemon path** — if standalone research stays reliable, consider removing complex strategic functions from researcher daemon codepath

**Pipeline Status:**
- ✅ Daemons restarted and new code loaded
- Cron: `0 23,3,7,11,15,19 * * *`
- Next run: 23:00 (ready)
- Real traces will replace mock traces once pipeline runs with outcome updates

---

## AutoTTS + Self-Evolution Integration (Completed `11f21b1c`)

**Integration Status:** Phases 1-4 complete. Researcher and controller now share data.

### Phase 1 ✅: Outcome Linking (Already Worked)
- `update-trace-outcomes` already hooked into experiment logging
- Traces now have `:outcomes` array with experiment results
- 12 traces with outcomes (8 kept, 4 discarded, 66.7% base rate)

### Phase 2 ✅: Dynamic Researcher Skill (`evolution.el`)
- **Helper functions:** `generate-source-effectiveness-section`, `generate-controller-guidance-section`, `generate-dynamic-instructions`
- **RESEARCHER.md now includes:**
  - Source effectiveness table (own-repo vs external with keep rates)
  - Controller guidance (thresholds, budget, priorities, topic models)
  - Dynamic instructions that adapt based on trace outcomes
  - Source strategy recommendations (e.g., "PRIORITY: Search davidwuchn/* repos FIRST")

### Phase 3 ✅: Controller Uses Self-Evolution Data (`strategic.el`)
- `get-self-evolution-topic-rate` — reads experiment TSVs for topic keep rate
- `adjust-thresholds-for-topic` — adjusts stop/branch thresholds based on topic performance
- High keep rate → lower stop threshold (keep researching)
- Low keep rate → raise stop threshold (stop early)

### Phase 4 ✅: Unified Evolution Hook (`evolution.el`)
- `evolve-all-skills` now calls `evolve-researcher-skill` before feedback analysis
- Single cycle: synthesize → consolidate → evolve skills → evolve researcher → AutoTTS strategy evolution

### Phase 5 ✅: Adaptive Prompts (`db7cfae8`)
- `build-adaptive-followup-prompt` — injects CONTINUE/BRANCH guidance per turn
- `run-research-turn` — passes controller decision between turns
- `build-followup-prompt` — deprecated, delegates to adaptive variant
- Tested: default (179 chars), CONTINUE (435 chars), BRANCH (501 chars)
- Pre-existing: heuristic BRANCH dead code (mutually exclusive conditions)
- **Note:** Daemon has persistent loading issue; functions manually defined after startup

### Test Results
- Batch test: 2 topic models (performance: 60% base, nil-safety: 80% base)
- Controller decision: STOP with topic-specific model for nil-safety
- Threshold adjustment: stop=0.70, branch=0.30 (no self-evolution data yet for nil-safety)
- Researcher evolution: generates dynamic RESEARCHER.md with source effectiveness

---

## Sync Review: Remote Optimization Experiments (Merged `0e4b6f4f`)

**Resolved:** Conflict in `token-efficiency.md` — took newest data (18544 chars, 119/748 experiments)
**Migrated:** `token-efficiency.md` moved from `assistant/skills/auto-workflow/` to `mementum/knowledge/` (learned data, not a skill)

**Incoming Changes (from remote optimize/* branches):**

1. **New strategy:** `strategy-semantic-compression.el` (62 lines)
   - Compresses function bodies to `...` while preserving signatures
   - Targets: `defun`, `defmacro`, `cl-defun`, `defadvice`
   - Hypothesis: Preserve interfaces, reduce tokens

2. **`gptel-agent-loop.el`** — Defensive guards
   - `continuation-prompt-for`: Validates task structure before processing
   - `compile-patterns`: Uses `proper-list-p` instead of `listp`

3. **`gptel-ext-context.el`** — Proper list validation
   - `extract-last-task`: Guards against non-list input

4. **`gptel-ext-fsm-utils.el`** — FSM robustness
   - Nil callback defaults to `#'ignore`
   - Pre-compiled FSM ID regex for O(1) matching

5. **`gptel-ext-retry.el`** — Message validation
   - Truncation: Checks `proper-list-p msg` before `plist-get`

6. **`gptel-benchmark-core.el`** — plist validation
   - `plist-to-alist`: Uses `proper-list-p` guard

**Pattern:** Remote experiments focused on **nil-safety hardening** — adding `proper-list-p` guards across multiple modules. This aligns with our nil-safety topic model (weight +2.0 for `source_own`).

**Sync Status:** ✅ Local + remote merged, pushed to `4cc93e30`

---

## Closure Fix for Multi-Turn Research (`217a5aea`)

**Problem:** `strategic.el` loads partially in daemon — only ~51 of ~60 functions defined. Critical functions (`run-research-turn`, `build-research-prompt`) missing.

**Root Cause:** Daemon loads file without lexical-binding, causing closure variables (`accumulated-findings`, `controller-config`) to fail in lambda callbacks.

**Fix:** Added global variables to avoid closure capture:
- `gptel-auto-workflow--research-accumulated-findings`
- `gptel-auto-workflow--research-total-tokens`
- `gptel-auto-workflow--research-controller-config`

**Status:** 
- ✅ Fix committed and pushed (`217a5aea`)
- ✅ Syntax validated
- ⚠️ Daemons need manual function eval after restart (file still loads partially)
- ⚠️ Researcher daemon down — needs restart

**Next Steps:**
1. Restart researcher daemon with fresh load
2. Manually eval missing functions if needed
3. Verify research produces findings > 0 chars
4. Check `var/tmp/research-findings.md` gets populated
