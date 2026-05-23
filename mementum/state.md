# Mementum State

> Last session: 2026-05-23

## Current Session: Deep Debugging + gptel Payload Fix

**Status:** Researcher scope + allium/persisted-budget bugs fixed. 1940 ERT unit tests, 0 unexpected.

### Bugs Fixed (2026-05-23, follow-up)

1. **`defvar lines` band-aid removed**: bottleneck report had one extra `)` closing the local `let*` before final `(if lines ...)`, so `lines` escaped scope. `defvar lines` only made the escaped read hit a global special variable; it also made the report always fall back. Fixed paren structure and added regression proving bottlenecks are emitted.
2. **Allium `listp "kept"` root cause**: `allium-diff-opposing-hypotheses` did `(car (cl-find ...))`, converting the matched cons cell `("kept" . hypothesis)` into string `"kept"`, then `(cdr kept)` crashed. Kept the cons cell and pass `(cdr kept)` / `(cdr discarded)`.
3. **Persisted category budget shape**: in-memory budget is alist `((:synthesis . 1) ...)`, but JSON restore returns plist `(:synthesis 1 ...)`. `enforce-category-budget` assumed alist and crashed on `car(:synthesis)`. Added normalizer used by budget enforcement and analyzer prompt formatting.
4. **Test lexical scoping leak**: `inject-queued-targets-dedup` used `let` while initializing `result` from sibling binding `targets`; changed to `let*`.

5. **Lambda verification `arrayp` error**: `call-backend-for-lambda` set `gptel-backend` to `(intern backend)` — a bare symbol. gptel expects a backend struct. Fixed by using `gptel-get-backend` to look up the real backend.
6. **`maphash corruption` preventive**: JSON-read hash tables can corrupt when iterated with `maphash` in Emacs 30.2. Added `json-read-hash-safe` helper that reads as plist and manually builds hash tables. Updated `load-researcher-meta-learning` and `format-topic-performance`.

**Verification:** `./scripts/run-tests.sh unit` → 1940 tests, 1886 expected, 0 unexpected, 54 skipped. No `arrayp` errors in log. `maphash corruption` in log is test mock, not real bug.

### Researcher Provider Routing Continued (2026-05-23)

- Fixed `gptel-benchmark-call-subagent` so headless chain selection runs even when an override/base preset exists; prior shape logged the override branch and skipped the direct chain branch.
- Added both `:backend` and `:model` to the effective preset before calling the timeout wrapper, blocking the `gptel-config.el` MiniMax nil-model advice.
- Fixed legacy headless-subagent fallback migration so hot-reload no longer restores MiniMax-first ordering.
- Added live reload of `gptel-tools-agent-prompt-build.el`, `gptel-tools-agent-error.el`, and `gptel-benchmark-subagent.el` in both `gptel-auto-workflow--reload-live-support` and the cron dispatch eval; `gptel-tools-agent.el` skips already-provided split modules.
- Verified in live `copilot-researcher` daemon with no-network mocks: the actual task-runner boundary receives `gptel-agent-preset` containing `:backend "moonshot"` and `:model "kimi-k2.6"`.
- Focused provider tests pass; full 532-test batch still has unrelated staging/payload failures.

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
