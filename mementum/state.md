# Mementum State

> Last session: 2026-05-16

## Current Session: Pipeline Hardening + Strategy Artifact Prevention

**Status:** Pipeline source loads clean; bad generated strategy artifacts are blocked before persistence.

**Commits This Session:**
- `f3da0801` — Fix garbage topic name leak + declare-function nil→correct + .gitignore pycache
- `26f1a954` — Fix case-mismatch in extract_topics regex
- `0980fcc9` — Merge + push to origin/main
- `aab097ad` — Fix trend detection, lookback filter, TRACE_DIR, evolve timestamp preservation
- `7688cf72` — Prevent bad strategy artifacts

**Key Fixes:**
- Strategy evolver REJECTED messages leaking into topic-performance.json as topic names
- Added `gptel-auto-workflow--valid-strategy-name-p` and `_valid_topic_name()` defenses
- `extract_topics_from_hypothesis` regex never matched: capitalized verbs in lowered text
- Trend detection, lookback filtering, undefined `TRACE_DIR`, and skill timestamp preservation fixed
- Strategy evolution prototype now exercises representative analysis data and rejects missing skill references before writing accepted strategy files
- Research knowledge synthesis now skips rejected diagnostic strategy labels, unsafe strategy names, `none`/`unknown`, and zero-kept strategies
- Added regressions for rejected research labels, zero-kept research strategies, placeholder strategy labels, dynamic missing skill references, and literal skill extraction
- 14 `declare-function nil` → correct source file across 9 files
- `__pycache__/` + `*.pyc` added to `.gitignore`

**Prior Session:**
- 377→11 byte-compile warnings, 2 End-of-file-during-parsing, cl-flet conversion
- Tool marker architecture, memory tools, progressive shortening

**Remaining Warnings (11, all cosmetic/unfixable):**
- 2 `(setf ...)` warnings: Emacs 30.2 ignores declare-function for setf
- 2 Malformed function: `cl-labels` byte-compiler limitation
- 5 cascade warnings from cl-labels Malformed function
- 1 `retire-buffer` not known: cl-labels local
- 8 "Cannot open load file: gptel" (pre-existing, needs gptel package)

**Test Results:**
- focused strategy-artifact regressions: 8/8
- changed module batch-load: clean
- `git diff --check`: clean
- research-benchmark: 19/19
- nucleus-tools: 28 pass + 2 skip (0 unexpected)

---
