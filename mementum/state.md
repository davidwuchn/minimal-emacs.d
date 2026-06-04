# Mementum State

> Last session: 2026-06-05 (Grader score parsing fix + byte-compile warnings)
> Next pipeline: running
> Status: 2231 tests, 0 unexpected, 0 byte-compile warnings

## Session: Grader Score Parsing + Pipeline Fixes (2026-06-05)

### ⊘ Fix: Grader score parsing uses caller total, not grader self-reported total
**Root cause:** Grader outputs `SCORE:3/9` (its own 9-point scale) but we specified
4 expected + 1 forbidden = 5 criteria. Parser used 9 as total → 3/9=33% < 60%
threshold → `grader-failed` decision despite 3/5 PASS.
**Fix:** `criteria-total` from expected+forbidden is authoritative. All 3 parse
paths (SCORE:X/Y, JSON, text PASS) now cap score to `criteria-total` and ignore
grader self-reported totals.
**Impact:** This was causing nearly all experiments to be marked `grader-failed`
even when the grader text said PASS. The pipeline was repeatedly attempting
the same nil-guard fixes (3+ times on `ontology-strategy.el`) because the
grader kept rejecting valid changes.

### ⊘ Fix: Nil-guard in ontology-strategy.el
`(cdr best)` → `(or (cdr best) 0)` in `gptel-auto-workflow--category-eight-key-weight`.
Pipeline had tried to fix this 3+ times but grader always rejected.

### ⊘ Fix: 16 byte-compile warnings → 0
- `gptel-auto-workflow-projects.el`: 4 `defvar`, 4 `declare-function` added
- `gptel-benchmark-subagent.el`: shortened 4 docstrings, prefixed unused
  variable, added 2 `declare-function`

### Commits
- `50c313530` ⊘ fix: 16 byte-compile warnings in projects.el and benchmark-subagent.el
- `785bdbe97` ⊘ fix: grader score parsing uses caller total, not grader self-reported total
- `37214d488` ⊘ fix: remove unused last-total variable from grade parser

---

### ⚒ P0: Schema Extraction + Frequency-Based Promotion
**New module:** `lisp/modules/gptel-auto-workflow-memory-schema.el`
- Hash-table-based schema index at `mementum/.ov5-memory-index.json`
- Heuristic triple extraction from memory text (verb+preposition patterns)
- Schema inference with frequency tracking
- τ=3 threshold: schemas need ≥3 observations before ontology router uses them
- Category lookup via entity matching (fallback for `categorize-target`)
- Conflict detection: entity overlap across multiple sources

**Integration:**
- `gptel-auto-workflow-mementum.el`: calls `extract-from-file` after `write-memory` and `synthesize-knowledge`
- `gptel-auto-workflow-ontology-router.el`: `categorize-target` checks schema index before defaulting to `:programming`

### ⚒ P1: Temporal Versioning
- New memories get `valid-from` frontmatter (YAML)
- `supersede-memory`: adds `valid-until` + `superseded-by` to old memory
- `read-valid-memories`: filters out superseded memories
- `find-superseded`: finds existing memories matching a slug for auto-supersession
- Auto-supersede wired into `write-memory`: existing memories with same slug are superseded

### ⚒ P1: Bidirectional Memory-Code Links
- `@memory:slug-name` references in code files scanned into reverse index
- `memories-for-file`: given code file, return referenced memory slugs
- `files-for-memory`: given memory slug, return code files referencing it

### ⚒ P2: Graph Retrieval (PPR-lite)
- Triple store for graph traversal (entity→schema→entity neighbor walk)
- `entity-neighbors`: find entities connected via shared schemas
- `retrieve`: multi-hop graph walk with score aggregation

### ⚒ P3: Hub Suppression (IDF Weighting)
- `entity-idf`: score = count * 1/log(deg+1) — penalizes generic entities, boosts rare
- `rank-entities`: IDF-weighted entity ranking
- `category-for-target` now uses IDF weighting instead of raw count

### Tests
- `tests/test-memory-schema.el`: 40 ERT tests covering all features
- 2229 total tests, 0 unexpected

---

### ⚒ GTM Daemon Auto-Restart (watchdog-daemon.sh)
**Problem:** GTM daemon (`gtm-product-org`) was dead for 2+ days — no research, stale findings
**Root cause:** Watchdog only monitored PMF daemon (`pmf-value-stream`); GTM daemon was killed on memory but never restarted
**Fix:**
- Added `start_gtm_daemon()` function to watchdog
- When PMF daemon is healthy, watchdog now checks if GTM daemon exists
- If GTM missing → starts it
- If GTM memory >2.5GB → kills + restarts it
- GTM daemon now running (PID 434201)

### ⚒ Rate-Limit Detection for Chinese Backends
**Problem:** Error code 1302 + "您的账户已达到速率限制" not recognized as rate-limit → experiments failed with `tool-error`
**Fix:** Added to `gptel-tools-agent-error.el`:
- Pattern: `您的账户已达到速率限制` (MiniMax account rate limit)
- Pattern: `1302` (error code)
- Both `rate-limit-error-p` and `hard-quota-error-p` functions updated

### ⚒ Staging Verification Fix — 'passed unexpectedly' treated as failure
**Problem:** Tests marked `:expected-result :failed` that actually passed were reported as "unexpected" by ERT, causing `run-tests.sh` to return failure
**Fix:** `scripts/run-tests.sh` now checks for actual FAILED tests; if only "passed unexpectedly" results exist, treats as success

### ⚒ Grader Bypass Commit Fix — merge commits in cherry-pick
**Problem:** Experiment commits are often merge commits; `git cherry-pick` without `-m` option fails with "no -m option given"
**Fix:** `gptel-tools-agent-staging-merge.el` detects merge commits via `git rev-parse --verify COMMIT^2` and adds `-m 1` flag

### ⚒ Analyzer Timeout Fix — 360→480s
**Problem:** Analyzer times out on complex files when using DeepSeek/CF-Gateway (slow fallback backends)
**Fix:** Increased `gptel-benchmark-subagent-slow-fallback-timeout` from 360 to 480 seconds

### Pipeline Audit Results
| Issue | Count | Status |
|-------|-------|--------|
| Rate-limit errors (24h) | 24+ | Fixed (detection + backoff) |
| GTM daemon dead | 1 | Fixed (auto-restart) |
| Analyzer timeouts | Multiple | Fixed (480s timeout) |
| Staging verification failed | Multiple | Fixed (unexpected passes OK) |
| Grader bypass commit failed | Multiple | Fixed (merge commit cherry-pick) |

### Commits
- `40ede3a0` ⚒ watchdog: auto-restart GTM daemon + rate-limit detection
- `4567dcd9` ⚒ test-runner: treat 'passed unexpectedly' as success
- `15c8b689` ⚒ staging-merge: handle merge commits in cherry-pick
- `60342ddf` ⚒ benchmark: increase slow-fallback timeout 360→480s

---

## Session: Self-Heal ERT Test Hardening (2026-06-05)

### ⊘ All 36 self-heal ERT tests now pass (was 34/36 with 2 expected failures)

**Root causes found and fixed:**

| Test | Root Cause | Fix |
|------|-----------|-----|
| `fix-let-needs-let*/sequential-binding` | `byte-compile-from-buffer` without `byte-compile-current-file` produced no line numbers; regex used ASCII quotes but Emacs 30+ uses Unicode | Set `byte-compile-current-file`; use `byte-compile--warning-source-offset` + `line-number-at-pos`; update regex to `[\u2018'\`]` |
| `fix-unknown-functions/adds-declare-for-known-module` | `function-exists-in-file-p` resolved paths from `default-directory` which was temp file dir, not project root | Cache project root at load time via `eval-and-compile` using `load-file-name` |

**Additional fixes:**
- `fix-condition-case` err-detection regex: same Unicode quote fix
- Test temp file: added `lexical-binding` directive (required for free-variable warnings)
- Removed `:expected-result :failed` from both tests

### Commits
- `0083443f1` ⊘ fix: missing close paren in self-heal-check when-healthy form
- `4a02cbeaf` ⊘ fix: all 36 self-heal ERT tests pass (was 34/36)

### Test Results
- **2189 total tests, 2137 passed, 0 unexpected, 52 skipped**
- 36 new self-heal tests all pass (was 34 pass + 2 expected-fail)

---

### ⚒ Phase 10: Self-Healing Byte-Compiler Warnings
**Key insight:** Instead of manually fixing 80+ byte-compiler warnings one-by-one
(whack-a-mole), created `gptel-auto-workflow--self-heal-byte-compiler` that
iteratively auto-fixes 5 warning types:

| Fixer | Warning Pattern | Auto-Fix |
|-------|----------------|----------|
| `--fix-docstring-width` | "docstring wider than 80 characters" | Word-wrap at 78 chars |
| `--fix-unescaped-quotes` | "unescaped single quotes" | `'word'` → `\='word\='` |
| `--fix-unused-variables` | "Unused lexical variable/argument" | Prefix with `_` |
| `--fix-free-variables` | "reference/assignment to free variable" | Insert `(defvar sym)` |
| `--fix-unknown-functions` | "function not known to be defined" | Insert `(declare-function sym "source")` via `find-lisp-object-file-name` |

**Architecture:** The function iterates up to N rounds, each round:
1. Collect warnings per file via `byte-compile-from-buffer`
2. Apply all 5 fixers
3. Re-check remaining warnings
4. Stop when clean or max iterations reached

**Dog-food principle:** The self-heal function should eat its own dog food —
run it on the files that still have warnings instead of manual fixes.

### ⚒ Zero-Warning Agent Modules
All `gptel-tools-agent-*.el` files compile with `byte-compile-error-on-warn t`.
Fixed via:
- 46 `declare-function` + 18 `defvar` forward declarations
- Circular dependency resolution (removed `eval-when-compile` requires
  that created cycles: main↔git, subagent↔git)
- `(with-no-warnings)` for `setf` struct accessors (`gptel-fsm-info`,
  `gptel-backend-models`) — byte-compiler can't see `gv-define-setter`
- `byte-compile-file` replaces `emacs-lisp-byte-compile-and-load` (wrong arity)
- Dead code removal (`in-think` tracking, `model-sym`)
- Soft require for `gptel-ext-backend-registry` (not on batch load path)
- `(require 'json)` at runtime (not just eval-when-compile) for `json-read-from-string`

### ⚒ Auto-Workflow Module Fixes (partial)
~30 warnings fixed manually in auto-workflow modules. Remaining ~35
(docstring width, free variables, unknown functions) are candidates
for the self-heal function to fix automatically.

### Commits
- `4844f6649` ⊘ fix: Eliminate all byte-compiler warnings in agent modules
- `6ba538578` ⚒ Phase 10: Self-healing byte-compiler warnings

---

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

### Fix 8: TDD test failure — backend-object with struct input (committed e8f126e1)
- **Problem:** `grader/uses-subagent-when-available` test failed in full suite with `wrong-type-argument stringp` — a `gptel-backend` struct was passed where a string was expected
- **Root cause:** Mock tests create backend structs; `gptel-auto-workflow--backend-object` only handled strings/symbols/keywords
- **Fix:** Added cond clause to return backend object as-is when input is already a struct

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
