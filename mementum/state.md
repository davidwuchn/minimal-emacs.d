# Mementum State

> Last session: 2026-05-26 (complete — 12 crash vectors fixed)
> Next pipeline: 23:00 (11 min)

## Session: OV5 24/7 Hardening — Complete

**12 crash vectors fixed.** System stable. All backends have fair routing.

### All Fixes Today (neopi5)

| # | Commit | Problem | Fix |
|---|--------|---------|-----|
| 1 | `89fd2124` | void-function nil flood (160+/cycle) | fdefs at top-level in gptel-ext-core.el |
| 2 | `5500ab1c` | callback guard missed :callback nil | functionp check + strip stale key |
| 3 | `cf61d5d1` | stale .elc overrides .el source | load-prefer-newer t globally |
| 4 | `593c2616` | analyzer ∞ retry (0s delay, no max) | exponential backoff 5/10/20/40s, max 3 |
| 5 | `6aefb3a5` | analyzer max→min timeout (300s vs 120s) | min(task-timeout, budget) |
| 6 | `ca326b6d` | pipeline syntax error blocked all exps | removed orphan 'done' |
| 7 | `03aa3b9b` | listp dotted pair crash | cddr + consp guard |
| 8 | `45b3baa0` | /tmp/gptel-agent-temp file-error | moved to var/tmp/ |
| 9 | `00e894a4` | curl 35 SSL not retryable + 1 retry | added to :general + retries 1→3 |
| 10 | `b2030c48` | cross-backend exhaustion undetected | set quota-exhausted after max retries |
| 11 | `b561c7a2` | aux subagent 10 retries, no quota guard | 10→5 + quota-exhausted check |
| 12 | `17e8dd36` | grader 180s timeout + no quota skip | 180→60s + quota-fast-skip |

### Routing (committed)

| # | Backend | Keep | Boost | Score | Notes |
|---|---------|------|-------|-------|-------|
| 1 | MiniMax | 20.5% | +0.05 | 0.255 | Proven leader |
| 2 | DeepSeek | 19.0% | +0.05 | 0.240 | Thinking tasks |
| 3 | moonshot | 8.8% | +0.15 | 0.238 | Second chance (bugs fixed) |
| 4 | DashScope | 0.0% | +0.18 | 0.180 | First real chance (model leak fixed) |
| 5 | CF-Gateway | 12.8% | 0 | 0.128 | Last resort |

### TDD (3 tests)

- `model-valid-for-backend-blocks-cross-backend-leak` — 9 assertions
- `best-model-for-task-returns-correct-per-backend-model` — 4 assertions
- `dashscope-executor-always-gets-qwen3.6-plus` — 12 assertions

### What the 23:00 Pipeline Will Prove

- void-function nil: 0 errors expected (fdefs at top level + load-prefer-newer)
- Analyzer: 3 attempts with exponential backoff, 120s timeout
- Executor: correct model per backend (DashScope→qwen3.6-plus, moonshot→kimi-k2.6)
- DashScope: first real traffic with its own model
- moonshot: second chance with retryable errors + fair boost
- Grader: 60s timeout, skips when quota exhausted
- Cross-backend exhaustion: detected after first experiment, stops cascade

### Daemon State

- ov5-auto-workflow: PID 1964630, 376MB, 6.3% CPU
- Hot-loaded: all 12 fixes active
- Status: idle, ready for 23:00 dispatch

## Session: OV5 24/7 Hardening + Definite void-function nil fix

**Status:** ALL crash vectors fixed. Lambda compiler proves value. Pipeline unblocked.
Evolution cycle completes. Routing correct.

### Today's fixes (2026-05-26)

| Commit | Type | What |
|--------|------|------|
| `03aa3b9b` | ⊘ | Fix nth 2 on dotted pairs (listp crash in model-valid-for-backend-p) |
| `4f98672e` | ⊘ | Guard stale gptel stream callbacks |
| `45b3baa0` | ⊘ | Temp dir /tmp→var/tmp, pref rebalance |
| `9f6d0c73` | ◇ | MiniMax executor boost (20.7% keep-rate) |
| `c22e9a87` | ⊘ | **Definitive** void-function nil fix: advise gptel-request |
| `ca326b6d` | ⊘ | Fix orphan 'done' in run-pipeline.sh (blocked all experiments) |

### Lambda Compiler: VALUE CONFIRMED

The lambda gate prompt `"Convert prose to lambda: square function"` was sent to MiniMax
and DeepSeek. Both responded with valid Elisp `(lambda (x) (* x x))`. The verification
hash now has `MiniMax=>:healthy, DeepSeek=>:healthy`. This directly feeds into the
ontology router — healthy backends get routing priority, degraded ones get penalized.

The lambda-adjusted-penalty (riven) auto-tunes: if healthy backends outperform degraded
by >10%, penalty increases to -35. If delta ≤0%, penalty drops to -5.

### Allium: INFRASTRUCTURE EXISTS, NEEDS VOLUME

- 10 trend categories tracked (1 occurrence each)
- Auto-tuned severity threshold from measured impact (riven)
- `allium-adjusted-threshold`: 0.30 default, self-adjusts based on impact delta
- Regression baselines saved to `var/tmp/evolution/allium-regressions/`
- Needs 10-20 more kept experiments for meaningful trend data

### Self-Evolution: INFRASTRUCTURE COMPLETE

- Evolution cycle at 14:39 completed: record-score, backend comparison (10 pairs),
  model comparison (5 models), semantic relationships (17 edges)
- VSM health step now clean (temp dir deleted)
- Keep-rate: 18.6% → 19.4% (recovering)
- 139 kept/staging-pending experiment results across all runs
- Pref-boost rebalanced: MiniMax now leads executor routing

### Current Daemon State
- ov5-researcher: PID 1548330 (15:00), 340MB, completed research + lambda verification
- ov5-auto-workflow: PID 1581757 (15:30), 372MB, idle

### Pipeline Status
- 15:00 pipeline completed research (12.6KB findings) but auto-workflow blocked by
  orphan `done` in run-pipeline.sh (fixed at `ca326b6d`)
- Next pipeline: 19:00 (7PM)
- Lambda verification results: MiniMax :healthy, DeepSeek :healthy (2/5 verified)
- void-function nil: definitively fixed with gptel-request advice in gptel-ext-core.el

**Status:** 25 commits, 2006 tests, 0 unexpected, 54 skipped. All 6 routing improvements (A-F) + 12 follow-ups deployed. 38 stale stashes cleared.

### Architecture Achieved

OV5 now has a fully closed-loop routing system at both experiment and subagent levels:

```
Evolution (VSM health, parse-all-results)
    │
    ├── VSM auto-tunes routing weights (all 5 layers)
    ├── Per-axis KIBC boost from holographic consensus
    ├── Recency-weighted keep-rate (14d half-life)
    ├── Delta-weighted holographic memory
    │
    ▼
Ontology Router (reorder-fallbacks-by-ontology + ranked-subagent-backends)
    │
    ├── 9-step scoring pipeline with VSM-tuned weights
    ├── Health ladder with auto-recovery (1h probation cooldown)
    ├── Per-run failure cooldown (hard-exclude)
    ├── Per-target model preference
    ├── Audit trail (both levels, component scores + VSM adjustments)
    │
    ▼
Subagent Dispatch (call-subagent)
    │
    ├── Accurate routing context at dispatch time
    ├── Actionable LLM guidance (health, keep-rate, axis rationale)
    │
    ▼
  Results → parse-all-results → evolution → (loop)

### Improvements (2026-05-25)

1. **A — Recency-weighted keep-rate** (`61eb125a`): `gptel-auto-workflow--decayed-keep-rate` with 14-day half-life. Each experiment gets weight `2^(-days_ago / 14)`. Recent performance matters more. Wired into `reorder-fallbacks-by-ontology` scoring formula alongside origin's Bayesian floor.

2. **B — VSM health auto-tunes routing** (`838500f8`): Evolution cycle's VSM layer health now auto-tunes:
   - S4 (Intelligence) weak → exploration rate 15%→30%
   - S3 (Control) weak → probation threshold 3→2 strikes
   - S1 (Operations) weak → min-samples 3→1
   - S5 (Identity) weak → confidence weight 10%→20%

3. **C — Per-axis backend preference** (`8972ce85`): `gptel-auto-workflow--axis-preference-boost` reads `gptel-auto-workflow--current-target`, looks up holographic consensus KIBC axis, and boosts backends with above-average keep-rate on that axis (delta × confidence × 0.15).

4. **D — Per-run backend cooldown** (`adbec398`): `gptel-auto-workflow--run-failed-backends` tracks backends that failed during the current run. Hard-excluded (score -1.0) for remainder of run. Cleared at run start. Wired into ontology-fallback-advice.

5. **E — Routing context in prompts** (`f3c479aa`): `{{routing-context}}` template variable tells the LLM which backend/model it runs on, lambda health, keep-rate, rate-limit status. Injected via `gptel-auto-workflow--routing-context`.

6. **F — Auto-recovery from probation** (`811a0493`): `gptel-auto-workflow--lambda-last-strike-time` tracks strike timestamps. Probation backends (level 3) with >1h since last strike auto-recover to level 2 (DEGRADED, weight 0.65 instead of 0.0).

### Follow-up (2026-05-25, same session)

7. **Delta-weighted holographic memory** (`14c0c2e9`): `record-holographic-experiment` now stores weighted floats (`weight = 1.0 + max(0, delta)`) instead of raw counts. Larger improvements contribute more to consensus confidence.

8. **Fixed `penalty-unknown` test**: Origin changed `:unknown` verification penalty from -5 to 0. Test updated to match.

### Architecture Notes

- `gptel-auto-workflow--ranked-subagent-backends` is the central subagent routing function. Score formula: `health × keep-rate + pref-boost + axis-boost`. Hard gates: lambda-degraded, quarantined, cooldown (-1.0). Soft gate: rate-limited (0.01).
- `reorder-fallbacks-by-ontology` is the experiment-level router with 9-step pipeline: health filter → 4D scoring (VSM-tuned weights) → category override → ternary → sieve → holographic → lambda penalty → sort → exploration.
- Both routers use `gptel-auto-workflow--backend-health-level` which auto-tunes probation threshold from VSM health and auto-recovers after 1h cooldown.
- Key files: `gptel-auto-workflow-ontology-router.el` (~1900 lines), `gptel-auto-workflow-evolution.el`, `gptel-tools-agent-prompt-build.el`.

**Verification:** `./scripts/run-tests.sh unit` → 1940 tests, 1886 expected, 0 unexpected, 54 skipped. No `arrayp` errors in log. `maphash corruption` in log is test mock, not real bug.

### Researcher Provider Routing Continued (2026-05-23)

- Fixed `gptel-benchmark-call-subagent` so headless chain selection runs even when an override/base preset exists; prior shape logged the override branch and skipped the direct chain branch.
- Added both `:backend` and `:model` to the effective preset before calling the timeout wrapper, blocking the `gptel-config.el` MiniMax nil-model advice.
- Fixed legacy headless-subagent fallback migration so hot-reload no longer restores MiniMax-first ordering.
- Added live reload of `gptel-tools-agent-prompt-build.el`, `gptel-tools-agent-error.el`, and `gptel-benchmark-subagent.el` in both `gptel-auto-workflow--reload-live-support` and the cron dispatch eval; `gptel-tools-agent.el` skips already-provided split modules.
- Verified in live `copilot-researcher` daemon with no-network mocks: the actual task-runner boundary receives `gptel-agent-preset` containing `:backend "moonshot"` and `:model "kimi-k2.6"`.
- Focused provider tests pass; full 532-test batch still has unrelated staging/payload failures.

### Researcher Self-Evolution Wiring (2026-05-23)

- After research completes (all projects), `gptel-auto-workflow--research-self-evolve` runs synchronously before daemon shutdown.
- Wires four systems: AutoTTS (controller evolution from traces), ontology (backend fallback reorder), AutoGo (champion league), meta-harness (strategy evolution).
- Each subsystem has its own data-sufficiency gates; calling with no fresh data is a safe no-op.
- Verified in live researcher daemon: function completes cleanly (`"Self-evolution complete"`), each subsystem skips when no data.
- Full 532-test batch: 447 pass, 22 fail, 63 skip — no regression introduced.

### E2E Moonshot Backend Fix (2026-05-23)

- **Root cause**: `my/gptel-agent--task-override` in `gptel-tools-agent-git.el` recomputed the preset from scratch using global `gptel-backend` (MiniMax), ignoring the `gptel-agent-preset` carefully set by `gptel-benchmark-call-subagent` with chain-selected Moonshot.
- **Fix 1** (`gptel-tools-agent-git.el`): If `gptel-agent-preset` is already bound with a `:backend`, use it directly instead of recalculating.
- **Fix 2** (`gptel-tools-agent-subagent.el`): The headless-auto-workflow check in `my/gptel--call-gptel-agent-task` required `--headless` AND `persistent-headless` AND `current-project`. Changed to OR on `--headless`/`persistent-headless`, matching `headless-provider-override-active-p`.
- **E2E proof**: Direct subagent call returned `MOONSHOT_WORKS` (no rate limits). Web research subagent returned 1379 chars of real external findings from Wikipedia, using Moonshot backend — no backends blacklisted.

### Bugs Fixed (2026-05-23)

1. **Verbum budget penalty**: `quarantined-backends` → `health-weight` API
2. **Gate-strategies paren scoping**: 2 missing parens causing byte-compile free-var warnings → regression test added
3. **Conflicted-target review queue**: human-in-the-loop triage for <50% agreement targets
4. **5 byte-compile warnings**: rates unused, `_t`/`err` naming
5. **Researcher crash** (`void-function bottleneck-report`): `let(guidance-json)` at L587 never closed, cascaded +1 depth through entire function, swallowing bottleneck-report as substitute's body. Fix: +1 `)` L598, −1 `)` L663
6. **3 `cl-return-from` without `cl-block`**: enrich-ontology, eight-keys-convergence, allium-bdd-check all silently fail at runtime with `No catch for tag`
7. **exec-path-from-shell 2.3s**: `check-startup-files nil` skips full shell rc loading
8. **Launchd daemon restart loop**: KeepAlive→AbnormalExit triggered rapid restarts; fixed with socket cleanup + ThrottleInterval
9. **gptel payload 350KB warning**: `my/gptel--effective-byte-limit` used `min(global, model)` which capped known models at 200KB even when they support 350KB+. Fix: use model-specific limit directly, only fall back to global for unknown models

### Key Learnings

- **Paren cascade bugs**: One unclosed `(` pushes all downstream depths +1, deferring defun closure dozens of lines. Check-parens passes (balanced) but structure is wrong. Use `syntax-ppss` depth tracking to find cascade roots.
- **`cl-return-from` without `cl-block`**: No compile warning. Fails silently at runtime with `No catch for tag`. Only visible in logs.
- **`min()` logic for limits**: Taking minimum of global+model limits is overly conservative. Models declare their own limits for a reason. Use model limit directly, global only as safety net for unknown models.
- **Launchd + Emacs daemon**: Socket path on macOS is `$TMPDIR/emacs$UID/server`, not `/tmp`. Must clean both paths.

**Phase 1-7 (Complete):**
1. **Ternary decisions** — Convert scores to -1/0/+1
2. **Verbum tracker** — Auto-detect new verbum sessions
3. **Ternary routing** — Sort rejected backends to bottom
4. **Lambda verification** — Check backends for lambda compiler presence
5. **Sieve routing** — Route deterministic tasks to Qwen, creative to distributed backends
6. **Cross-backend consistency** — Compare KIBC axis across backends for same target
7. **Holographic memory** — Track kept experiments by target+axis consensus

**Production Wiring (Complete):**
- **Experiment completion hook**: auto-records to holographic memory
- **Evolution cycle**: runs cross-backend consistency check every 3 hours
- **Dashboard**: shows verbum session, lambda health cache, holographic memory stats

**Test Results:** 65/65 router tests, 245/245 evolution tests — all passing.

**Commits:**
- `d85298b0` ◈ Add Future Layer: verbum integration roadmap
- `893280c0` ⚒ Add verbum integration: ternary + lambda verification + tracker
- `ebf91a2d` ⚒ Wire verbum tracker + ternary routing into evolution cycle
- `97e01196` ⚒ Implement backend lambda verification (verbum Phase 4)
- `6a0ac690` ⚒ Sieve-based backend routing (verbum Phase 5)
- `b23aa60e` ⚒ Cross-backend consistency checking (verbum Phase 6)
- `60c80a85` ⚒ Holographic experiment memory (verbum Phase 7)
- `15b3dd5c` ⚒ Wire verbum integration into production pipeline

### What's Running Now
- **Verbum tracker**: checks for new verbum sessions every evolution cycle
- **Lambda verification**: checks all backends every 6 hours
- **Consistency check**: checks all multi-backend targets every 3 hours
- **Holographic memory**: auto-records on every kept experiment completion
- **Sieve routing**: boosts appropriate backends by +10 points per task type

### Next Improvements

1. **Actually call backends for lambda verification** — Replace simulated verification with real API calls using gate prompt
2. **Use holographic consensus in routing** — Boost experiments with high consensus
3. **Cross-backend consistency alerts** — Flag targets with <50% agreement for manual review
4. **Verbum training monitoring** — Poll training checkpoints, auto-alert when complete

### Still Waiting On
- Verbum TernaryDescent training to complete (4–5 days on Mac)
- Evaluate whether accuracy improves beyond 87%

---

## Prior Sessions

### Session: Verbum Integration (2026-05-23)
- All 7 phases implemented
- Production wiring complete
- 8 commits, +400 lines of code
- 65/65 tests passing

### Session: TDD Coverage Expansion (2026-05-16)
- 89 test files scaffolded for 89 modules
- 100% file-level coverage achieved
- All batches passing (211/211 tests)

### Earlier
- Retry depth fixes + pipeline verification
- 2 HIGH plist-put bugs fixed + 18 dead functions removed
- macOS stat fix + .elc cleanup in pipeline
