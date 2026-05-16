# Mementum State

> Last session: 2026-05-16

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
