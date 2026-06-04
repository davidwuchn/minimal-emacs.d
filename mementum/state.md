# Mementum State

> Last session: 2026-06-04 (Pipeline hardening + Fix OOM kills + staging-pending loss + deprecated models)
> Next pipeline: running
> Status: 2150 tests pass, 0 unexpected

## Session: Pipeline Hardening — Python3 Elimination + Grader Fix (2026-06-04)

### ⚒ Eliminate python3 dependency from all pipeline scripts
**4 scripts, 8 python3 invocations replaced with pure bash:**

| Script | Replacements |
|--------|-------------|
| `run-auto-workflow-cron.sh` | 5: file-age→stat+date, socket→lsof+bash, status→sed, emacsclient→timeout(1) |
| `watchdog-daemon.sh` | 1: socket probe→bash path loop + lsof fallback |
| `install-cron.sh` | 1: crontab merge/remove→awk |
| `run-tests.sh` | 1: touch backdate→GNU touch -d |

**New helper:** `find_server_socket()` — deduped candidate paths (XDG_RUNTIME_DIR, TMPDIR, /tmp)

**Net change:** -265 lines, removes python3 as runtime dependency entirely

### ⚒ Fix "Unknown agent type: grader" — root cause of grader-failed experiments
**Problem:** Benchmark subagent types (grader/analyzer/reviewer/explorer) not registered in `gptel-agent--agents`
**Fix:** `gptel-benchmark--register-subagent-types()` auto-registers on load + `with-eval-after-load 'gptel-agent`

### ⚒ Commit-recovery fix (previous session continuation)
`experiment-core.el`: When commit step reports failure but HEAD changed (submodule restage race), detect via hash comparison and treat as success instead of `grader-bypass-commit-failed`.

### ⚒ Hashline collision reduction
`hashline.el`: hash length 2→4 chars (1/256 → 1/65536 collision probability)

### Pipeline audit findings
- **CRITICAL:** python3 PATH broken in cron → research got zero external findings every run
- **CRITICAL:** "Unknown agent type: grader" → experiments scored 0 → grader-failed
- **HIGH:** Researcher daemon dead since Jun 3, only PMF running → stale research
- **FIXED:** All 3 critical issues addressed in this session

### Commits
- `f5162f4b` ⚒ Fix grader-bypass-commit-false-negative + hashline collision rate
- `0c16f041` ⚒ Eliminate python3 dependency from all pipeline scripts
- `68130dd2` ⚒ Register benchmark subagent types in gptel-agent--agents

---

## Session: 2026-06-04 — Critical Fixes

### Fix 1: Staging-pending experiments lost (committed 297e40f1)
- **Problem:** Experiments that passed grading were logged as "staging-pending" but never completed
- **Root cause:** `finish-publish` in staging-merge.el had stale-run guard — when async staging outlived workflow run, `run-callback-live-p` returned nil → experiment silently discarded
- **Fix:** Replaced guard with `progn`+`when` — staging always executes, stale run just logs warning

### Fix 2: Deprecated MiniMax models blocking tests (committed ab70dc78)
- **Problem:** Test `tdd/cost/model-pricing-has-cache-for-deepseek-minimax` failing because it checked removed models `minimax-m2.7-highspeed` and `minimax-m2.7`
- **Root cause:** We removed deprecated models from backend registry but not from test expectations or `gptel-ext-backends.el`
- **Fix:** Removed deprecated models from test, `gptel-ext-backends.el`, and backend registry

### Fix 3: Daemon OOM-killed every 30 minutes (committed ab70dc78)
- **Problem:** Daemon grew to ~5GB RSS within 30 min, system OOM killer killed it before watchdog could restart gracefully
- **Root cause:** Watchdog memory threshold was 5GB — same as OOM killer trigger point
- **Fix:** Lowered watchdog threshold from 5GB to 2.5GB for both workflow daemon and researcher daemon

### Fix 4: Prioritize DeepSeek for executor (committed 243a0850)
- **Problem:** MiniMax-M3 consistently fails to call Edit/Write tools — 90%+ experiments produce 0 file changes
- **Root cause:** MiniMax-M3 was primary executor model; it reads files but ignores edit mandates
- **Evidence:** DeepSeek-v4-flash produced 1.00/1.00 scoring experiment (runtime.el fix on 2026-06-03)
- **Fix:** Reordered executor task-type defaults and fallback chain — DeepSeek first, MiniMax second

### Fix 5: Blacklist MiniMax for executor (committed 8d23a029)
- **Problem:** Drift-forced swap logic was still putting MiniMax first for some targets
- **Fix:** Removed MiniMax entirely from executor fallback chain and task-type defaults
- **Result:** Executor now uses: DeepSeek → moonshot → DashScope → Copilot

### Fix 6: Backend capture "unknown" (committed d1556f21)
- **Problem:** Experiment TSVs logged backend as "unknown" even when model was known
- **Root cause:** `gptel-backend` is nil during headless subagent execution; preset extraction also failed
- **Fix:** Added fallback to derive backend from `gptel-model` using `gptel-auto-workflow--backend-for-model`

### Fix 7: Protected files in target selection (committed 6e09c8b9 + 814b5fa2)
- **Problem:** Analyzer repeatedly selected `lisp/modules/gptel-auto-workflow-strategic.el` which is protected → experiments scored 1.00/1.00 but were blocked by validation → 0 kept
- **Root cause:** `frontier-select-targets` didn't filter protected files; they have small frontiers (0 experiments kept) so they ranked highest
- **Fix:** 
  1. Added protected file filter after category health check in `select-targets`
  2. Added protected files list to analyzer prompt as explicit exclusion rule

---

> Previous session: 2026-06-03 (Dual Mayor Phases 5-7 complete)
> Status: 2149 tests pass, 0 unexpected — Dual Mayor fully operational

## Session: Dual Mayor Implementation Complete (2026-06-03)

**Phases 5-7 implemented:**

### Phase 5: Cross-Mayor Communication
- `lisp/modules/gptel-auto-workflow-beads.el` — Bead protocol (GTM↔PMF communication)
- `mementum/decisions/` — Human decision gate directory + template
- `gptel-auto-workflow--pending-decisions-p` — Blocks PMF dispatch when decisions pending (configurable)
- Auto-file beads from research findings, auto-update from experiment results
- Bead protocol status + decision gate surfaced in evolution dashboard

### Phase 6: Full Separation
- `mementum/gtm/strategy-roadmap.md` — Strategy template that GTM writes, PMF reads
- `gptel-auto-workflow--read-gtm-strategy` / `--write-gtm-strategy` — Strategy I/O functions
- GTM auto-start runs strategy evolution periodically
- PMF reads strategy focus at start of each `run-async` call
- `assistant/commands/pmf-mayor-run.md` — Discrete PMF command reference
- `assistant/commands/gtm-mayor-research.md` — Discrete GTM command reference
- Fixed: reverted broken `projects.el` from commit 1407ecf20 (parse error)

### Phase 7: Innovation Metrics
- `gptel-auto-workflow--pmf-metrics` — experiments/day, keep-rate %, hours/validation
- `gptel-auto-workflow--gtm-metrics` — findings/day, strategy accuracy %, PMF signal
- Dashboard templates updated with metric placeholders (`var/tmp/pmf-dashboard.md`, `gtm-dashboard.md`)
- Auto-update metrics on experiment/research completion

### Critical Fix: MiniMax Model Name (all subagents)
- **Problem:** All experiments failing with `grader-failed` — `minimax-m2.7-highspeed` model timing out/rate limited
- **Root cause:** Commit 1407ecf20 only fixed executor; analyzer, grader, researcher, reviewer, comparator still used broken model
- **Fix:** Updated all subagent presets in:
  - `lisp/modules/gptel-ext-backend-registry.el` — task-type-model-defaults
  - `lisp/modules/gptel-tools-agent-prompt-build.el` — per-task-model-map
- **Result:** All subagents now use `MiniMax-M3` (working model)

### Bug Fixes During Integration
- **Metrics dashboard `(invalid-function 0)`**: `gptel-auto-workflow--update-dashboard` received numeric values from plists; `replace-regexp-in-string` tried to call them as functions. Fixed by wrapping all numeric values with `(format "%s" ...)`.
- **Git conflict markers in prompt-build.el**: Resolved leftover `<<<<<<< Updated upstream` / `>>>>>>> Stashed changes` markers from earlier stash operations.
- **Sieve type generation for DashScope**: Commit `b49c20701` dynamically generated sieve types from `gptel-backend-registry` but only checked backend names for "qwen". DashScope backend name doesn't contain "qwen" (its models do). Fixed to check model names too.

**Tests:** 2149 pass, 0 unexpected, 52 skipped

**All 7 phases of Dual Mayor implementation plan complete + all integration bugs fixed.**
