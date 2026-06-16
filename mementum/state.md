# Mementum State

> **Last pipeline**: 2026-06-16 18:31 (zero-run)
> **Next pipeline**: scheduled
> **Plan**: /home/davidwu/.emacs.d/mementum/knowledge/plans/pipeline-runs/run-20260616-190000/
>
> **Bootstrapped**: 2026-06-06
> **Session**: Dual REPL Architecture (daemon-repl + Clojure brepl)
> **Status**: ⊘ ✓ **STATECHART MODULE TDD COVERAGE EXPANDED** — 21/21 tests pass. Fixed real bug: `statechart-analyze` used unbound `gate-order` (only bound in `build-statechart`). Added TDD tests for `detect-compensating-errors`, `extract-gate-score-vectors`, `statechart-analyze`, `statechart-drift-check`. 592-line module went from 4 → 21 tests.
> **Latest**: Pushed `09bd678f7` — drift-check TDD coverage.

---

## Session Note (2026-06-16 — Duplicate daemon creation bug fix)

1. **Root cause identified**: Auto-workflow not producing experiments
   - Pipeline log showed "Auto-workflow queued: :completed" but no experiments produced
   - Status file showed `:running t :phase "running"` but daemon not responding to emacsclient
   - Found **5 duplicate pmf-value-stream daemons** and **2 duplicate gtm-product-org daemons** running simultaneously
   - All competing for the same socket, causing emacsclient timeouts

2. **Bug in `ensure-worker-daemon!`** (`clj/ov5/pipeline/daemon.clj`)
   - Function checked if daemon was alive (line 256-258)
   - But didn't return early — continued with cleanup and launch steps
   - Each pipeline run created a new daemon without killing the old one
   - Result: multiple daemons competing for same socket

3. **Fix applied**
   - Wrapped cleanup/launch code in `do`-block within `if`-else
   - Now returns `:already-running` immediately if daemon is alive
   - Prevents duplicate daemon creation

4. **Cleanup performed**
   - Killed all duplicate pmf-value-stream daemons (5 → 0)
   - Killed all duplicate gtm-product-org daemons (2 → 0)
   - Cleaned stale sockets in /tmp/emacs501/

5. **Verification**
   - Clojure syntax test passed
   - Committed as `110589252`

### Impact
- Auto-workflow should now execute properly without daemon conflicts
- Pipeline should produce experiments as expected
- No more emacsclient timeouts due to socket contention

---

## Session Note (2026-06-16 — Helium-inspired caching implementation)

1. **Studied Helium architecture** (`/tmp/helium_demo`)
   - Helium uses three-level caching: prompt cache, KV cache, intermediate results
   - Cache-aware scheduling (CAS) orders operations to maximize prefix reuse
   - Key insight: cache identical LLM calls and expensive intermediate computations within a run

2. **Implemented response cache** (`lisp/modules/gptel-ext-prefix-cache.el`)
   - Caches LLM responses keyed by `(backend . model . prompt-hash)`
   - Integrated into `my/gptel--run-agent-tool-with-timeout` for non-executor subagents
   - LRU eviction (max 500 entries), per-run isolation
   - 9 new tests, all passing

3. **Implemented intermediate result cache** (`lisp/modules/gptel-ext-prefix-cache.el`)
   - Caches expensive computations like target categorization
   - Integrated into `gptel-auto-workflow--categorize-target`
   - LRU eviction (max 1000 entries), per-run isolation
   - 8 new tests, all passing

4. **Verification**
   - All prefix-cache tests: 49 tests passing (41 original + 8 intermediate)
   - All ontology-router tests: 31 tests passing
   - All subagent tests: 50 tests passing
   - No regressions in existing functionality

5. **Expected impact**
   - Reduced redundant LLM calls (response cache)
   - Reduced redundant categorization computations (intermediate cache)
   - Lower token costs and faster experiment cycles

### Next steps
- Monitor pipeline runs to measure actual cache hit rates
- Consider adding more intermediate result types (baseline quality scores, etc.)
- Update mementum knowledge with Helium comparison

---

## Session Note (2026-06-16 — daemon environment + self-heal coverage)

1. **Restarted pipeline and diagnosed failures**
   - Old daemon (started before fixes) was in a `server-start` restart loop, producing `End of file during parsing: post-init.el`.
   - Newer daemon ran but project was skipped: `[auto-workflow] Cron error at step "cleanup-worktrees": Searching for program: Permission denied, gpg`.
   - Root cause: `clj/ov5/pipeline/daemon.clj` replaced the child process environment with `env-opts` that omitted `PATH`, so `gpg` was not found and `.authinfo.gpg` could not be decrypted.

2. **Fixed daemon environment** (`clj/ov5/pipeline/daemon.clj`)
   - Added `"PATH" (or (System/getenv "PATH") "")` to `env-opts` so spawned Emacs daemons inherit the parent PATH.
   - Verified in fresh pipeline run: `[eca-security] Credentials loaded from /Users/davidwu/.authinfo.gpg`.

3. **Added self-heal semantic audits so OV5 can detect/fix alone**
   - `daemon-server-start`: flags explicit `(server-start)` in init files (safe only inside `(when (not (daemonp)) ...)`).
   - `daemon-launcher-env`: flags `clj/ov5/pipeline/daemon.clj` `env-opts` missing `PATH` or `TMPDIR`.
   - Fixers registered for both issue types.

4. **Verification**
   - `test-self-heal-semantic` targeted run: 154 tests, 154 results as expected, 0 unexpected.
   - Fresh pipeline run started successfully, daemon loads without `End of file during parsing`, research completes with external findings.
   - Auto-workflow is running (researcher subagent still active); monitoring for experiment production.

### Next steps
- Monitor current pipeline run for first successful experiments.
- Consider adding runtime PATH/gpg sanity check at daemon startup.

---

## Session Note (2026-06-16 — daemon restart loop + pre-commit false positives)

1. **Fixed daemon restart loop / `End of file during parsing`** (`post-init.el`)
   - Removed explicit `(server-start)` call inside the `(when (daemonp) ...)` block.
   - The `--daemon` flag already starts the server after init files load; calling `server-start` during init saw an unbound `server-process`, stopped/restarted the server, and reloaded init files, racing into `End of file during parsing` on macOS.

2. **Fixed daemon socket path environment** (`clj/ov5/pipeline/daemon.clj`)
   - Added `"TMPDIR" "/tmp"` to `env-opts` for the spawned Emacs process.
   - Babashka's process `:env` replaces the parent environment entirely, so `TMPDIR` from `run-pipeline.sh` was lost and `emacsclient` could not find the daemon socket.

3. **Fixed pre-commit hook false positives** (`.git/hooks/pre-commit`)
   - `top_level_def_after_line_1_p` regex matched `defun` inside strings (e.g., test fixtures with `(defun foo`).
   - Added `skip_strings_and_comments` helper using `syntax-ppss` to skip string/comment content before scanning for top-level defs.
   - Pre-commit hook now correctly ignores `defun` inside strings and comments.

4. **Added self-heal semantic audit for `server-start` in daemon init**
   - New audit: `daemon-server-start` — flags `(server-start)` calls in `post-init.el`, `post-early-init.el`, `init-*.el` that are not guarded by `(when (not (daemonp)) ...)`.
   - Auto-fixer wraps unguarded `(server-start)` in `(when (not (daemonp)) (server-start))`.
   - Prevents future daemon restart loops from this root cause.

5. **Added self-heal semantic audit for daemon launcher env**
   - New audit: `daemon-launcher-env` — flags `clj/ov5/pipeline/daemon.clj` `env-opts` missing `PATH` or `TMPDIR`.
   - Auto-fixer injects missing env vars into the `env-opts` map.
   - Prevents future daemon environment issues from this root cause.

6. **Verification**
   - `check-parens` clean on all modified `.el` files.
   - `bash -n` clean on `scripts/run-pipeline.sh`.
   - `test-self-heal-semantic`: 154 tests, 154 results as expected, 0 unexpected.
   - Pre-commit hook passes on staged files.
   - Committed as `096175ac6`.

---

*Active Mementum v1.1 — duplicate daemon bug fixed, Helium-inspired caching implemented, daemon environment hardened*

## Session Note (2026-06-16 — statechart module TDD coverage)

1. **Discovered real bug via TDD**: `statechart-analyze` called
   `detect-compensating-errors` with `gate-order` (unbound in its scope).
   The variable is only bound in `build-statechart`. Any test calling
   `statechart-analyze` directly would throw `void-variable gate-order`.
   Fix: use `gates` (which IS bound in statechart-analyze).

2. **Added 13 TDD tests** to `tests/test-pipeline-statechart.el`:
   - 5 for `detect-compensating-errors` (early-fail+high-grader, low-grader
     ignored, no-early-fails ignored, mixed input, empty input)
   - 4 for `statechart-analyze` (returns required keys, bottleneck is
     lowest p-pass, lossiest-gate is highest abs fail, phi keep-rate-max
     is positive)
   - 3 for `statechart-drift-check` (identical no drift, drops above
     threshold, improvement no alert)
   - 5 for `extract-gate-score-vectors` (uses existing vector, fallback
     to compute, skip record with no data, empty input, preserves order)

3. **Module coverage**: 4 → 21 tests for the 592-line statechart module.
   6 of 12 defuns now have TDD coverage.

### Next steps
- Add TDD tests for: build-statechart, statechart-rebuild-and-persist,
  statechart-report, statechart-show
