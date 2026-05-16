# Mementum State

> Last session: 2026-05-16

## Current Session: Pipeline E2E Feedback-Loop Hardening

**Status:** Real `scripts/run-pipeline.sh` completed once with 16 experiments, then targeted fixes made the research → results.tsv → trace-outcome feedback path observable and test-covered.

**Key Findings:**
- Real e2e run: research succeeded, self-evolution ran, auto-workflow completed 16 experiments, but every result row had `research_hash=none` / `research_quality=none`.
- Root cause: `gptel-auto-experiment-log-tsv` called `plist-put` without capturing the returned plist, so research metadata was silently dropped before writing `results.tsv`.
- Secondary gap: workflow daemon could load persisted findings for prompts without reconstructing `gptel-auto-workflow--current-research-context`, preventing trace outcome linking after daemon restart.
- Pipeline smoke exposed researcher timeout/orchestration gaps: missing findings now generates local fallback research, stops the lingering researcher daemon, and avoids proceeding with no research signal.

**Source Fixes:**
- `gptel-auto-workflow-strategic.el`: reconstructs research context from persisted findings and matching trace JSON.
- `gptel-tools-agent-prompt-build.el`: captures `plist-put` returns for research metadata and staging-failure downgrade metadata.
- `scripts/run-pipeline.sh`: validates research feedback loop, fails researcher waits on timeout, stops timed-out researcher, writes local fallback findings/internal research.
- `tests/test-gptel-tools-agent-regressions.el`: added regressions for `results.tsv` research metadata and persisted findings context restoration.

**Verification:**
- Real e2e before fixes: `2026-05-16T113305Z-0b4d/results.tsv`, 16 experiments, 0 improved, research metadata missing.
- Smoke after fixes: fallback path generated usable internal research and self-evolution completed with `research: internal`.
- Targeted ERT: research feedback regressions passed; researcher daemon strategic regressions passed.
- Full unit suite: `1795 tests, 1688 expected, 0 unexpected, 107 skipped`.

**Caution:**
- Pipeline/self-evolution generated many skill and mementum knowledge edits. Treat them as generated output, separate from source fixes unless deliberately committing evolution artifacts.

---

## Current Session: Second Audit Pass — plist-put Bugs + Dead Code Sweep

**Status:** All known `plist-put` return-value bugs fixed. 26 dead functions removed (315+ lines). 57 tests green.

**Commits This Session:**
- `a995f4e8` — Fix 3 HIGH bugs + dead code + axis consolidation (first audit pass)
- `06c71a9b` — Fix 2 HIGH plist-put bugs + missing requires + 18 dead functions (second audit pass)

**Key Fixes (First Audit):**
- `push` on `plist-get` silently dropped all data in `consolidate-insights` (9 sites) → `plist-put` + `setq` + `puthash`
- `plist-put` return value discarded for `:avg-quality` in `strategic-daemon-functions.el` (4 sites)
- Missing `(require 'seq)` in `evolution.el`, missing requires in `prompt-build.el`
- Removed 8 dead functions, unified axis-name mapping, deprecated `nth` file-attribute accessors

**Key Fixes (Second Audit):**
- `plist-put` return value discarded in `strategic.el:919` (`:digested` key) → `setq` capture
- `plist-put` return value discarded in `git.el:438` (`:tracking-marker` key) → `setq` capture
- Added `(require 'cl-lib)` + `(require 'subr-x)` to subagent, experiment-loop, worktree
- Added `(require 'subr-x)` to staging-merge
- Removed 18 more dead unreferenced functions across 5 files

**Total plist-put Bug Class Fixed:**
- `push` on `plist-get` (9 sites in evolution.el) — data silently dropped
- `plist-put` return discarded with new keys (6 sites across 3 files) — new key/value silently dropped
- Pattern: `plist-put` mutates in-place for existing keys but returns a NEW plist for new keys

**Prior Session:**
- 377→11 byte-compile warnings, cl-flet conversion, tool marker architecture
- Pipeline hardening, strategy artifact prevention

**Remaining Warnings (11, all cosmetic/unfixable):**
- 2 `(setf ...)` warnings: Emacs 30.2 ignores declare-function for setf
- 2 Malformed function: `cl-labels` byte-compiler limitation
- 5 cascade warnings from cl-labels Malformed function
- 1 `retire-buffer` not known: cl-labels local
- 8 "Cannot open load file: gptel" (pre-existing, needs gptel package)

**Test Results:**
- 57 tests, 53 pass, 0 unexpected, 4 skip

---
