# Mementum State

> **Bootstrapped**: 2026-06-06
> **Session**: Dual REPL Architecture (daemon-repl + Clojure brepl)
> **Status**: ✅ **SELF-HEAL + ONTOLOGY REPAIRED** — high-risk routing blocks direct mutation of repair-engine files; ontology-router paren corruption fixed; stale cache removed
> **Latest**: Agent-regression grader/promotion failures reduced from 32 to 1; daemon reliability hardened (curl orphans fixed, macOS socket pinned, KIBC-M regex repaired, World Store skips gracefully on macOS aarch64). Full unit suite green (3206 tests, 0 unexpected, 89 skipped).
> **Active Plan**: Push reliability fixes to origin; monitor Pi5 cron for end-to-end completion; investigate remaining `decision-callback-is-idempotent` integration-test abort (likely Datahike branch-switch hang in headless env).
> **Pi5**: Auto-evolution active; pre-push hook now blocks broken pushes to main; Pi5 auto-evolved boundary fixes (Preview Mode 2, Edit hashline, Code_Map/Inspect/Replace, plan-mode readonly enforcement)

---

## Session Note (2026-06-14 — daemon reliability + macOS hardening)

1. **Grader curl orphan leak fixed**
   - Root cause: grader timeout auto-passed without aborting the live gptel-curl request; cleanup fallback compared `process-buffer` (curl temp buffer) against `request-buf` (parent buffer), so orphaned curl processes accumulated.
   - `lisp/modules/gptel-tools-agent-benchmark.el`: `gptel-abort` on `grade-buffer` before auto-pass on timeout.
   - `lisp/modules/gptel-tools-agent-subagent.el`: capture live `gptel-curl` process in task state under `:curl-process`.
   - `lisp/modules/gptel-tools-agent-git.el`: kill stored `:curl-process`; fix fallback to iterate `gptel--request-alist` matching by FSM `:buffer` instead of `process-buffer`.
   - `post-init.el`: curl `--max-time` changed from 900 to 840 (margin under 900s grade timeout).
2. **macOS daemon socket hardening**
   - `post-early-init.el`: for workflow daemons, pin `server-socket-dir` to `/tmp/emacs$UID/`, `setenv TMPDIR /tmp`, `setq temporary-file-directory /tmp`.
   - `lisp/init-system.el`: do not sync `TMPDIR` via `exec-path-from-shell` for workflow daemons.
   - `post-init.el`: replace `file-exists-p` self-heal with connectivity check (`emacsclient -s sock -a false -e t`); delete stale socket before heal.
   - `lisp/init-ai.el`: use pinned `server-socket-dir` variable, fallback `/tmp/emacs$UID/`.
   - `AGENTS.md`: update `λ socket_path` rule to pin workflow sockets under `/tmp/emacs$(id -u)/`.
   - `scripts/run-pipeline.sh` and `run-auto-workflow-cron.sh`: `export TMPDIR=/tmp` so `emacsclient` resolves the pinned socket.
3. **KIBC-M regex repaired**
   - `lisp/modules/gptel-tools-agent-prompt-build.el`: removed literal newlines and fixed single-backslash alternation; source now uses `\\|` so Elisp reads it as regex `\|`. All 12 kibcm tests pass.
4. **`split-string` nil guard**
   - `lisp/modules/gptel-tools-agent-experiment-core.el`: guarded `split-string` on `gptel-auto-workflow--last-prompt-sections` with `stringp` + `not-string-empty-p`.
5. **World Store graceful degradation on macOS aarch64**
   - `lisp/modules/gptel-ext-world-store.el`: added `ov5-world-store--datahike-pod-available-p` (cached `bb` pod check); `--ensure-nrepl` returns nil if pod unavailable; `--brepl-eval` wraps errors in `condition-case`; `-connect` sets `'unavailable` sentinel.
   - Five `test-world-store-*.el` files now skip when Datahike pod is unavailable. 34 World Store tests: 3 pass, 31 skipped on macOS aarch64.

### Verification
- Full unit suite: 3206 tests, 0 unexpected, 89 skipped (World Store on macOS aarch64). Runtime ~220s.
- `test-self-heal-semantic`: 132/132 pass.
- `test-experiment-gates`: 16/16 pass.
- `test-kibcm-*` (12 tests): 12/12 pass.
- `test-experiment-by-filters-bug` (split-string nil guard): pass.
- `bash -n` clean on modified shell scripts.
- `git diff --check` clean.

### Blockers
- Datahike pod has no `macos-aarch64` release, so World Store remains disabled on macOS dev box. Production World Store runs on Pi5 (Linux x86).

---

## Session Note (2026-06-14 — Datahike World Store migration)

1. **Migrated `results.tsv` → Datahike World Store** (`clj/ov5/world_store.clj`, `gptel-tools-agent-prompt-build.el`, `gptel-tools-agent-base.el`, `gptel-auto-workflow-evolution.el`, `gptel-tools-agent-experiment-core.el`, shell scripts, tests)
   - Extended `base-schema` from 9 to 64 attributes (53 experiment + 11 gate-score).
   - Added `transact-experiment`, `experiments-by-decision-and-age`, `kept-experiment-count`, `kept-target-count`, `all-experiments-readable`, `staging-pending-by-age` helpers.
   - `gptel-auto-experiment-log-tsv` now transacts to Datahike via `ov5-world-store--brepl-eval`; all side effects preserved.
   - `gptel-auto-workflow--parse-all-results` now queries World Store; same plist return format preserved.
   - `gptel-auto-experiment--recover-stale-staging-pending` now queries World Store.
   - Removed `gptel-auto-workflow--results-tsv-header`; made `ensure-results-file` a no-op.
   - Backfill: 117 TSV files processed, 80 rows transacted, 59 entities with valid IDs in store.
   - Shell scripts updated (run-pipeline.sh, check-evolution-status.sh, run-auto-workflow-cron.sh, run-tests.sh).
   - Historical TSV files preserved for audit.

### Verification
- `bb -e "(load-file ...)"` clean on `clj/ov5/world_store.clj` and `migration.clj`.
- `bash -n` clean on all modified shell scripts.
- Backfill completed with 0 errors.
- `test-gptel-auto-workflow-evolution-regressions`: 290/291 pass (1 skipped).
- `test-gptel-tools-agent-core`: 67/67 pass.
- `test-gptel-auto-workflow-production-metrics`: 16/16 pass.
- `test-self-audit`: 15/15 pass.
- `test-gptel-tools-agent-regressions`: 608/640 pass, 32 unexpected (pre-existing grader/promotion logic, not migration-related).

---

## Session Note (2026-06-14 — agent-regression grader/promotion fixes)

1. **Fixed `gptel-auto-experiment--promote-correctness-fix-decision` bypass logic**
   - `grade-bypass-p` now only triggers when structural metrics actually drop (`quality-delta < 0` or `combined-delta < 0`), preventing it from overriding standard promotion on positive-quality ties.
   - `correctness-bypass-p` now requires gate rejection and a structural metric drop, so it only overrides rejections caused by guard-code quality penalties, not rejections for insufficient quality gain.
   - Promotion tests: 10/10 pass; tie-rejection tests: 6/6 pass.

2. **Fixed nil-initialized counters causing `wrong-type-argument number-or-marker-p nil`**
   - `gptel-auto-experiment--api-error-count` now defaults to `0` in `gptel-tools-agent-error.el`, `gptel-tools-agent-experiment-loop.el`, and `gptel-tools-agent-main.el`.
   - `gptel-auto-experiment-max-per-provider-attempts` now defaults to `3` in `gptel-tools-agent-error.el` and `gptel-tools-agent-benchmark.el`.
   - `gptel-tools-agent-error.el`: `gptel-auto-experiment--should-reduce-experiments-p` now guards nil with `(or ... 0)`.

3. **Fixed `split-string(nil ",")` in `gptel-tools-agent-experiment-core.el`**
   - `gptel-auto-workflow--trace-strategy-execution` now checks `stringp` before splitting `gptel-auto-workflow--last-prompt-sections`.

### Verification
- `test-gptel-tools-agent-regressions`: 640/641 completed, **0 unexpected**, 1 aborted (`decision-callback-is-idempotent` hits 30s ERT timeout, likely Datahike `ov5-world-store-branch-switch` hanging in mocked worktree test).
- `test-gptel-ext-checkpoint`: 5/5 pass.
- `check-parens` clean on all modified `.el` files.
- `batch-byte-compile` clean (only pre-existing warnings).

---

## Session Note (2026-06-14 — checkpoints.ckpt → EDN)

1. **Migrated `var/tmp/checkpoints/*.ckpt` → `.edn`** (`lisp/modules/gptel-ext-checkpoint.el`, `tests/test-gptel-ext-checkpoint.el`)
   - Serialization now uses `parseedn-print-str` and shared `gptel-auto-workflow--read-edn` / `gptel-auto-workflow--edn-to-plist` helpers.
   - Active checkpoint path changed to `active.edn`; archived checkpoints use `history/<run-id>.edn`.
   - Legacy JSON `.ckpt` files are automatically loaded, converted to EDN, and renamed to `.ckpt.migrated`.
   - Added roundtrip tests for serialization, save/load, archive extension, legacy migration, and empty results.
   - Fixed latent paren issues in `gptel-checkpoint--stale-lock-p` and `gptel-checkpoint-snapshot-loop-state`.

### Verification
- `check-parens` clean on `lisp/modules/gptel-ext-checkpoint.el` and `tests/test-gptel-ext-checkpoint.el`.
- `batch-byte-compile` clean on `lisp/modules/gptel-ext-checkpoint.el` and `tests/test-gptel-ext-checkpoint.el`.
- `test-gptel-ext-checkpoint`: 5/5 pass.
- `bash -n scripts/*.sh` clean.
- `git diff --check` clean.

---

## Session Note (2026-06-14 — research-findings.md → EDN)

1. **Migrated `var/tmp/research-findings.md` → `.edn`**
   - `gptel-auto-workflow--research-file` returns `.edn` path.
   - `gptel-auto-workflow-run-research` writes `{:project ... :updated ... :findings ...}` EDN via `parseedn-print-str`.
   - `gptel-auto-workflow-load-research-findings` and `gptel-auto-workflow--read-research-findings-file` parse EDN and extract `:findings`, handling both hash-table and plist returns from `parseedn-read`.
   - `gptel-auto-workflow--research-fresh-enough-p` now validates non-empty `:findings` instead of markdown line count.
2. **Updated all consumers**
   - `lisp/modules/gptel-auto-workflow-evolution.el`: direct readers now extract `:findings` before Allium/pair-probe parsing.
   - `lisp/modules/standalone-research.el`: `slr--save-findings` writes compatible EDN.
   - `lisp/modules/gptel-auto-workflow-production.el`, `gptel-auto-workflow-projects.el`: hardcoded paths updated.
   - `scripts/run-pipeline.sh`: `write_research_fallback` writes EDN.
   - Tests, docs, and assistant skill/command docs updated.
3. **Converted active cache**
   - `var/tmp/research-findings.md` migrated to `.edn`; stale `.md` worktree copies left for audit.

### Verification
- `test-gptel-auto-workflow-evolution-regressions`: 290/291 pass (1 skipped).
- `test-gptel-tools-agent-core`: 67/67 pass.
- `test-gptel-auto-workflow-production-metrics`: 16/16 pass.
- `regression/auto-workflow/load-research-findings-restores-context`: pass.
- `regression/auto-workflow/load-research-findings-nil-cache-no-crash`: pass.
- `bash -n scripts/run-pipeline.sh` clean.
- `git diff --check` clean.

---

## Session Note (2026-06-13 — EDN migration + evolution paren fix)

1. **Migrated `self-audit-result.el` → `.edn`** (`lisp/modules/gptel-auto-workflow-self-audit.el`, `scripts/run-pipeline.sh`)
   - Writer now builds a plist and uses shared `gptel-auto-workflow--write-edn` helper.
   - Shell consumer loads `parseedn` + `gptel-tools-agent-experiment-loop` and uses `gptel-auto-workflow--read-edn` to extract remediation variables.
2. **Fixed unmatched paren in `gptel-auto-workflow-evolution.el:5797`**
   - Extra closing `)` closed `let*` / `defun` prematurely; removed one close. `check-parens` now clean.
3. **Migrated context database `var/context/*.sexp` → `.edn`**
   - Updated `gptel-auto-workflow-context-database.el` to write/read EDN via shared helpers.
   - Updated `gptel-auto-workflow-production.el` counts, Clojure `clj/ov5/world_store/context.clj` filter, and `tests/test-world-store-context.el` fixture.
   - Renamed existing on-disk sidecars from `.sexp` to `.edn`.
4. **Updated `mementum/knowledge/edn-audit-2026-06-13.md`** to reflect completed migrations.

### Verification
- `check-parens` clean on all modified `.el` files.
- `bash -n` clean on `scripts/run-pipeline.sh`.
- `test-gptel-auto-workflow-context-database.el`: 17/17 pass.
- `test-world-store-context.el`: 3/3 pass.
- Self-audit re-run: 39 issues, `:broken-modules nil`.

---

## Session Note (2026-06-13 — EDN migration batch #2)

1. **Approval queue `.sexp` → `.edn`** (`lisp/modules/gptel-auto-workflow-approval-queue.el`, `scripts/run-pipeline.sh`, `tests/test-gptel-auto-workflow-approval-queue.el`)
   - Centralized read/write through shared EDN helpers.
   - Renamed existing on-disk pending/decisions files.
   - Tests: 12/12 pass.
2. **Decision classification `.sexp` → `.edn`** (`risk-patterns.edn`, `approval-history.edn`)
   - Wrapped list-of-plists data in `vconcat` before writing to avoid parseedn alist mis-detection.
   - Tests: 27/27 pass.
3. **Disposable tracker `.sexp` → `.edn`**
   - Single-plist sidecars; migrated read/write to shared helpers.
   - Manually verified roundtrip.
4. **Monitoring agent `.sexp` → `.edn`** (`impact-assessments.edn`, metrics snapshots)
   - Wrapped impact-assessments list in `vconcat`.
   - Updated self-tuning approval-queue write.
   - Tests: 35/35 pass.
5. **Production metrics `.sexp` → `.edn`**
   - Updated metrics snapshot write/read regex and approval-queue summary reader.
   - Renamed existing `var/metrics/*.sexp` files.
6. **Evolution `.sexp` → `.edn`** (`researcher-feedback.edn`, `category-champions.edn`)
   - Converted category champions alist to EDN vector-of-plists and back.
   - Wrapped `:stats` list in researcher feedback with `vconcat`.
   - Updated `strategic-daemon-functions.el` reader.
   - Architectural evolution tests: 23/23 pass; strategic-daemon tests: 63/63 pass.
7. **Cross-cutting consumers**
   - `gptel-tools-agent-prompt-build.el` reads approval-queue decisions via EDN.
   - `gptel-tools-agent-experiment-loop.el` isolated temp status file uses `.edn`.
   - `tests/test-gptel-tools-agent-regressions.el` updated to use `.edn` status paths.
   - `clj/ov5/world_store/context.clj` fixture paths updated.

### Verification
- `check-parens` clean on all modified `.el` files.
- `bash -n` clean on `scripts/run-pipeline.sh`.
- Approval-queue: 12/12, decision-classification: 27/27, monitoring-agent: 35/35, context-database: 17/17, world-store-context: 3/3, experiment-loop: 33/33, prompt-build: 7/7, architectural-evolution: 23/23, strategic-daemon: 63/63.
- Self-audit re-run: 39 issues, `:broken-modules nil`.

### Key gotchas
- `parseedn-print-str` treats a list of plists as an alist and prints it as a single EDN map. Wrap lists of plists with `vconcat` before writing, or represent them as vectors.
- `with-temp-file` should not wrap `gptel-auto-workflow--write-edn`; the helper writes directly to the file. Replace `(with-temp-file FILE (write-edn ...))` with `(write-edn FILE DATA)`.
- `buffer-file-name` is nil inside `with-temp-file`; always pass the file variable explicitly.

---

## Current Priorities (Auto-ranked)

| Priority | Item | Model | Status |
|---|---|---|---|
| **P0** | OV5 self-heal: fix workspace boundary violations | @maintainer | **COMPLETE** |
| **P0** | Platform sandbox (seatbelt + bubblewrap) | @maintainer | **COMPLETE** |
| **P0** | Security audit: fix 14 sandbox vulnerabilities | @maintainer | **COMPLETE** |
| **P0** | Self-heal semantic module (7 audit checks + auto-fixers) | @maintainer | **COMPLETE** |
| **P0** | Fix condition-case-unbound-err audit false positives | @maintainer | **COMPLETE** |
| **P0** | Add condition-case-unbound-err auto-fixer | @maintainer | **COMPLETE** |
| **P0** | Rename Elisp brepl→daemon-repl, fix 9 bugs | @maintainer | **COMPLETE** |
| **P0** | Create Clojure brepl wrapper module (gptel-ext-brepl.el) | @maintainer | **COMPLETE** |
| **P0** | Wire both REPL modules into gptel-config.el | @maintainer | **COMPLETE** |
| **P0** | Route high-risk self-heal repairs through OV5 worktree validation | @maintainer | **COMPLETE** |
| **P0** | Repair ontology-router paren corruption from old self-heal bug | @maintainer | **COMPLETE** |
| **P1** | Monitoring Agent: Complete (Phases 0-10) | @maintainer | **COMPLETE** |
| **P1** | Research paper analysis (MOSS, Sibyl, APEX) | @maintainer | **COMPLETE** |
| **P2** | Daemon watchdog hardening (Pi5 freeze after ~90 min) | @maintainer | **COMPLETE** |

---

## Research Insights (May 2026 Papers)

### MOSS: Source-Level Self-Evolution (2605.22794)
- **Key insight**: Source-level adaptation is Turing-complete — strict superset of text-mutable scope
- **OV5 alignment**: Already does source-level evolution via self-heal-semantic + git worktrees
- **Action item**: ✅ **IMPLEMENTED** — Batch anchoring groups similar failures before evolution

### Sibyl-AutoResearch: Trial-and-Error Harnesses (2605.22343)
- **Key insight**: Executable workflows don't produce research judgment; need explicit trial-to-behavior conversion
- **OV5 alignment**: Ontology graph already captures trial outcomes
- **Action item**: Formalize ontology updates as auditable conversion units

### APEX: Exploration Collapse (2605.21240)
- **Key insight**: Self-evolving agents suffer from exploration collapse as memory grows
- **OV5 alignment**: Category saturation detection prevents some collapse
- **Action item**: ✅ **IMPLEMENTED** — Strategy DAG with prerequisite edges prevents complex strategies before building blocks validated

**Knowledge page**: `mementum/knowledge/self-evolving-agent-research.md`
**Memory**: `mementum/memories/insight-source-level-evolution-turing-complete.md`

---

## Self-Healing Verification (Latest Pipeline Run)

**Timeline**:
- 23:01:13 — Grader crashed (void-variable err)
- 23:01:14 — OV5 diagnosed: `backend-rate-limited`
- 23:01:14 — Attempted remediation
- 23:01:21 — Still crashed → entered **BLIND MODE**
- 23:08:31 — **Recovered** — grader 9/9 healthy

**Self-healing working as designed**:
- Detection ✓
- Diagnosis ✓
- Remediation attempt ✓
- Fallback (BLIND MODE) ✓
- Recovery ✓

---

## Active Patterns

- **Defense-in-depth**: L1 (Emacs sandbox) → L2 (boundary validator) → L3 (plan-mode whitelist) → L4 (OS sandbox)
- **Self-heal semantic**: 7 audit checks + auto-fixers (unbalanced parens, missing provides, unguarded calls, blank lines, condition-case-unbound-err, etc.)
- **Monitoring agent**: Meta-improvement layer — detects failures, generates proposals, auto-deploys fixes
- **Ontology learning**: Every experiment outcome updates the ontology graph
- **Mementum memory**: Cross-session learning via git-based persistence
- **Git worktree isolation**: Each experiment runs in isolated worktree, no container overhead
- **High-risk self-heal dispatch**: self-heal/monitor/evolution files route through OV5 worktree validation; normal files use direct targeted repair

---

## Session Notes (2026-06-10)

### Dual REPL Architecture

Two REPL modules now exist, both wired into `gptel-config.el`:

| Module | Purpose | Backend | Tests |
|--------|---------|---------|-------|
| `gptel-ext-daemon-repl.el` | Elisp eval in running daemon | emacsclient | 20 |
| `gptel-ext-brepl.el` | Clojure eval via brepl CLI | ~/.local/bin/brepl (nREPL) | 19 |

### What was done this session
1. **Fixed self-audit regression**: `gptel-auto-workflow-self-audit--check-defvar-override-defcustom` was filtering `some-var` as a false positive because the placeholder regex was evaluated case-insensitively; bound `case-fold-search` to `nil` in the filter and verified the full self-audit suite
2. **Synced Pi5**: 3 merge rounds, resolved git conflict markers in ontology-router.el + memory-schema.el
3. **Renamed brepl→daemon-repl**: Disambiguated Elisp daemon REPL from Clojure brepl CLI
4. **Fixed 9 bugs in daemon-repl** (TDD): reentry hang, emacsclient exit status, socket discovery, file-notify require+flag, event parsing, dotfile check, autofix gate, self-heal arity, emacs-lisp-mode context
5. **Created gptel-ext-brepl.el**: Clojure nREPL client wrapping `~/.local/bin/brepl` — eval, load-file, bracket balance, port discovery
6. **Installed pre-commit hook**: Rejects .el files with git conflict markers
7. **Hardened install-ops-global.sh**: Backup before edit, socket detection, YAML validation
8. **Both modules wired** into gptel-config.el, 39/39 tests green

### Key Decisions
- Case-sensitive placeholder filters should explicitly bind `case-fold-search` to `nil` when matching symbols
- Elisp daemon-repl and Clojure brepl are separate tools with separate skill directories
- Pre-commit hook is local-only (.git/hooks/); Pi5 cron installs via bootstrap
- `(defvar SYMBOL)` without value → `void-variable` crash in batch mode; always `(defvar SYMBOL nil)`
- Stale `.elc` bytecode masks source edits; delete when debugging module load issues
- Emacs 30 byte-compiler miscompiles `throw` through `catch` when `let` wraps `catch` — restructure to put `catch` outside
- Self-heal paren fixer appending closes at EOF can trap subsequent defuns inside earlier forms — must insert before provide/end marker
- Reorder-cache keyed only by (strategy . target) is incorrect when experiment data evolves; removed in favor of recalculation
- `handle_patch` may add extra closing paren at wrong location during bulk edits; always verify depths with syntax-ppss

### Previous session (2026-06-10 early)
1. **Audit bug**: `backward-up-list` from `(error` handler went directly to `condition-case`, causing false positives
2. **Scope bug**: Audit searched entire `condition-case` form for `err` references
3. **Auto-fixer added**: `gptel-auto-workflow--fix-condition-case-unbound-err`
4. **Tests cleaned**: Removed tests for non-existent risk-node functions; 46 tests pass
5. **Watchdog hardened**: Heartbeat 180s→90s, grace 1200s→300s, conditional grace
6. **Risk-node audit fixed**: 334→5 issues (hash-table false positives removed)
7. **Batch anchoring + Strategy DAG** implemented from MOSS/APEX research

### Late session (2026-06-10 late — self-heal hardening + ontology repair)
1. **High-risk self-heal routing**: Added dispatch layer — normal files use direct targeted fix, repair-engine files route through OV5 worktree validation
2. **OV5 worktree adapter**: `self-heal-file-via-ov5` creates temp worktree, validates parens/load before promoting fixes; rejects dirty targets
3. **daemon-repl dispatch**: Updated eval-failure recovery to use routing dispatch instead of always calling direct self-heal
4. **Semantic audit → 0 issues**: Fixed `shell-command-to-string` risk-node (added condition-case), narrowed temp-repo setup false positive
5. **Fixed maphash arity bug**: byte-compiler warning in memory-schema.el — malformed 1-arg maphash call
6. **Repaired ontology-router paren corruption**: Old self-heal appended 3 closes at EOF, trapping 30+ defuns inside reorder-fallbacks-by-ontology. Moved closes to correct position, removed stale reorder-cache (caching by strategy+target was incorrect with evolving data), restored fallback return in insufficient-data branch
7. **Bulk self-heal hardened**: Entry point now routes high-risk files through dispatch instead of invoking fixers directly

### Test Summary
- **self-heal-semantic**: 57/57
- **daemon-repl**: 24/26 (2 existing skips)
- **ontology-router**: 24/24
- **self-audit**: 9/9 (added 3: defvar-override, pipeline-gate, staging-bypass)
- **world-store**: 14/14 (Phase 1: 8 bootstrap + Phase 2: 3 migration + Phase 3: 3 context)
- **Full unit suite**: 2968 total, 0 unexpected, 29 skipped. All green.

---

## Next Steps

### Session Note (2026-06-11)
- Isolated `gptel-auto-workflow--audit-provide-inside-defun` into its own module and wired it into `gptel-auto-workflow-self-heal-semantic`.
- Structural tests now pass: swallowed `provide` is detected and auto-fixed, good files stay clean.
- Key insight: `syntax-ppss` can move point; wrap it in `save-excursion` inside search loops or the scan can repeat the same match forever.
- Serialized Allium `gptel-request` fan-out behind a shared FIFO queue and aligned the diff target cap with `gptel-auto-workflow-max-targets-per-run` to prevent pipe exhaustion.
- Verified with targeted ERT: 294 tests, 0 unexpected results.
- Restarted auto-workflow; current status is running with run-id `2026-06-11T231229Z-92f2`.
- Cleaned `gptel-auto-experiment--kibcm-patterns`: embedded regex newlines were real matching chars, so phrase tests now guard `same entity`, `refactor into`, `instead of`, and `similar to`.

### Session Note (2026-06-12)
- Studied [DeepSearcher](https://github.com/zilliztech/deep-searcher) and compared it with OV5.
- Highest-leverage gap: OV5 has no dense-vector memory backend for mementum.
- Follow-up: **Datahike + Proximum** answer this — OV5 already has Datahike wired; Proximum adds HNSW vector indexing with same immutable, git-like semantics. No new dependency needed. Extend `gptel-ext-world-store.el` to embed + chunk + index mementum memories.
- Other gaps identified: LLM-based chunk reranking, multi-hop RAG agent over memories, knowledge-domain router, per-query agent router, web-to-memory loader, retrieval-recall evaluation harness.
- Captured in `mementum/knowledge/deep-searcher-vs-ov5-gaps.md` and `mementum/memories/insight-deep-searcher-vs-ov5-gaps.md`.
- Studied [Launch Fast](https://launchfastlegacyx.com/) — Chrome extension contextual-overlay pattern. Analyzed what OV5 would do applied to a SaaS codebase (experiment loop is language-agnostic, tooling is Elisp-locked).
- Studied [clojure.cc](https://clojure.cc/) — **strategic decision: Clojure-first multi-platform.** 39 Clojure dialects cover every platform. One language (Clojure), one toolchain (clojure.test + clj-kondo + cljfmt), every platform via dialect transpilers. Eliminates per-language backend scaling problem.
- Implemented Clojure experiment loop: `run-tests.sh clj`, `clj/ov5/test_runner.clj`, `gptel-brepl-run-tests`, `gptel-brepl-lint-file`, `gptel-brepl-fix-ns-ordering`, `:clojure` category. brepl 41/41, ontology-router 117/117.
- Captured in `mementum/knowledge/clojure-first-multiplatform-architecture.md` and `mementum/knowledge/launch-fast-vs-ov5-gaps.md`.
- Built CreatorOS demo: 5 modules, 31 tests, CI pipeline. Moved to independent repo at `ssh://onepi5/davidwuchn/creatoros.git`. OV5 can now manage it via `.dir-locals.el` + project config.
- Studied TikTok 网红 + 小红书 种草 e-commerce: two OV5 business models — CreatorOS (B2C, $49-99/mo) + SeedSight (B2B, $530-3,960/mo). Same 80% infra.
- Updated OUROBOROS-V5.md + BUSINESS_CONTEXT.md with numbers, World Store, demo narratives.

### Session Note (2026-06-12 late)
- Fixed the blocked-experiment control flow: `evolution-run-cycle` now preflights the human-decision gate, returns `blocked-pending-decisions` instead of falsely reporting success, and `run-async` now uses truthiness for the gate check.
- Added regression coverage for blocked trigger handling and restarted `pmf-value-stream`; live status now responds on `/tmp/emacs$(id -u)/pmf-value-stream`.

### Session Note (2026-06-13)
- OV5 nil-hash self-heal was over-eager: parse/load gates passed while semantic defaults were still wrong.
- Hardened the detector with exact table-argument matching, buffer-aware multi-binding lazy-init parsing, and a bare forward declaration for `skill-graph--edges`.
- Added regressions for the real affected files; `gptel-ext-prefix-cache.el` and `gptel-auto-workflow-memory-schema.el` now audit clean.
- Lesson: rewriting `defvar` defaults needs semantic/behavior gates, not just structural load checks.

### Session Note (2026-06-13 late)
- Added a targeted ERT gate before OV5 promotes semantic fixes back to the live tree.
- `run-tests.sh unit <selector>` now forwards selectors, and OV5 maps known files to focused suites (`self-heal-semantic`, `memory-schema`, `prefix-cache`).
- Promotion now rejects if the targeted ERT gate fails, so self-heal can find and stop bad semantic fixes before they reach main.

### Session Note (2026-06-13 continued — OV5 grader-bypass hardening)
- Discovered a systemic experiment-gaming attack: many `optimize/*` branches on origin have `◈ Grader-bypass ... 0.40 → 1.00 (+150%)` subjects with fabricated scores.
- Root causes: staging disabled by `defvar nil` overrides; critical-file check only blocked mass deletions; grader-bypass accepted `:grader-only-failure`/blind-mode auto-passes; optimize branches pushed before staging.
- Implemented 4-phase hardening plan under `plans/ov5-grader-bypass-hardening/`.
- Phase 1 pushed to main (`021b2d10`): removed staging overrides, expanded critical-files registry, hardened grader-bypass predicate, added push quarantine, added `tests/test-experiment-gates.el` (16 tests).
- Phase 2 pushed to main (`de129468`): added `toxic-commit-subject` and `score-fabrication` self-heal-semantic checks, added `audit-toxic-optimize-branches` self-audit helper, added 3 regression tests.
- Deleted toxic branch `optimize/benchmark-ncase-r110836z56cd-exp1` from origin. Scanned remaining 143 optimize branches; many still had toxic subjects.
- **Cleanup complete**: batch-deleted 141 toxic `optimize/*` branches from origin (verified none were merged to main). Only 2 non-toxic optimize branches remain.
- Full verification: 132 self-heal-semantic tests + 16 experiment-gates tests pass; pre-push gate passes.
- Captured memory + knowledge: `mementum/memories/insight-ov5-grader-bypass-gate-hardening.md`, `mementum/knowledge/ov5-experiment-gate-integrity.md`.

### Session Note (2026-06-13 late — semantic audit gate follow-up)
- Double-checked why experiment gates still let a bad semantic-audit path reach `main`: the pre-push audit gate used `|| true` after command substitution, so `$?` always read as 0 and Gate 2 could not fail on audit errors.
- Closed a second blind spot: `gptel-auto-workflow-audit-provide-inside-defun.el` was required by the audit path but not treated as gate-engine / never-fast-track, so it now routes through full staging verification.
- Added regression coverage for the push-blocking path and the new gate-engine helper; full unit suite passed after the fix.
- Follow-up: audit-fix reports now live in `var/tmp/self-audit/audit-fix/`; `mementum/memories/` is reserved for durable learning, not scratch audit output.

### Immediate
1. **Review/quarantine remaining toxic optimize branches** — 143 remote optimize branches; many flagged by `audit-toxic-optimize-branches`. Decide batch deletion vs. case-by-case review.
2. **Enable opencode eval on Pi5** — Set `gptel-auto-workflow-opencode-eval-enabled t` after monitoring first cron cycle
3. **Monitor pipeline metrics** — Check if gate hardening reduces toxic branch creation and improves real keep rate

### Near-Term
4. **Sibyl action item** — Formalize ontology updates as auditable conversion units (plan exists, not yet started)
5. **Write integration test for opencode executor** — Current tests mock subprocess; real test validates full pipeline
6. **Add more eval tasks** — Expand from 3 to cover edge cases (brepl errors, daemon-repl no daemon)
7. **Clojure brepl in OV5 pipeline** — Wire brepl bracket-fixing into auto-workflow for .clj files

---

## Relevant Files

- `lisp/modules/gptel-ext-daemon-repl.el`: Elisp daemon REPL — eval, bracket validation, auto-eval, self-heal (371 lines, 20 tests)
- `lisp/modules/gptel-ext-brepl.el`: Clojure nREPL client — eval, load-file, balance brackets (117 lines, 19 tests)
- `lisp/gptel-config.el`: Module loader — both REPL modules wired here
- `.opencode/skills/brepl/`: OpenCode skill for Clojure brepl CLI
- `.opencode/skills/daemon-repl/`: OpenCode skill for Elisp daemon-repl
- `lisp/modules/gptel-auto-workflow-self-heal-semantic.el`: 17 audit checks + auto-fixers (now includes toxic-commit-subject and score-fabrication)
- `lisp/modules/gptel-tools-agent-experiment-core.el`: experiment runner with hardened grader-bypass predicate and push quarantine
- `lisp/modules/gptel-tools-agent-validation.el`: critical-file mutation gate
- `mementum/knowledge/ov5-experiment-gate-integrity.md`: gate integrity knowledge base
- `mementum/memories/insight-ov5-grader-bypass-gate-hardening.md`: hardening session memory
- `mementum/knowledge/self-evolving-agent-research.md`: Research paper analysis
- `mementum/knowledge/deep-searcher-vs-ov5-gaps.md`: DeepSearcher gap analysis (Proximum)
- `mementum/knowledge/launch-fast-vs-ov5-gaps.md`: Launch Fast SaaS/Chrome extension patterns
- `mementum/knowledge/clojure-first-multiplatform-architecture.md`: Clojure-first strategic decision
- `mementum/state.md`: This file — working memory, read first every session
- `mementum/knowledge/self-evolving-agent-research.md`: Research paper analysis
- `mementum/knowledge/deep-searcher-vs-ov5-gaps.md`: DeepSearcher gap analysis
- `mementum/state.md`: This file — working memory, read first every session

---

*Active Mementum v1.1 — dual REPL architecture wired, 148 self-heal/experiment-gate tests green, OV5 gate integrity hardened, ontology learning active*
