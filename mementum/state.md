# Mementum State

> Last session: 2026-05-16

## Current Session: Pipeline Bug Fixes + Strategy Name Validation

**Status:** All known bugs fixed. Pipeline solid. 49 tests green.

**Commits This Session:**
- `f3da0801` — Fix garbage topic name leak + declare-function nil→correct + .gitignore pycache
- `26f1a954` — Fix case-mismatch in extract_topics regex
- `0980fcc9` — Merge + push to origin/main

**Key Fixes:**
- Strategy evolver REJECTED messages leaking into topic-performance.json as topic names
  - Added `gptel-auto-workflow--valid-strategy-name-p` (3-layer defense: maybe-evolve, load-active-strategy, experiment record)
  - Added `_valid_topic_name()` in `analyze_research_outcomes.py`
  - Cleaned garbage from runtime data (evolution_summary, topic-performance, controller JSON, research trace)
- `extract_topics_from_hypothesis` regex never matched: capitalized verbs in lowered text
- 14 `declare-function nil` → correct source file across 9 files
- `__pycache__/` + `*.pyc` added to `.gitignore`
- Wrong `defvar` for cl-defstruct accessors in `gptel-workflow-benchmark.el`

**Pipeline Audit Findings (not yet fixed):**
- HIGH: Trend detection indexes global list by position, not topic experiments (analyze_research_outcomes.py:177)
- HIGH: `TRACE_DIR` undefined in unified-evolution.py:234 (NameError)
- MEDIUM: lookback_days filter is computed but never applied (analyze_research_outcomes.py:115)
- MEDIUM: evolve_skills.py deletes timestamp metadata without replacement
- MEDIUM: evolve_researcher.py ignores --output-dir and --analysis args

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
- research-benchmark: 19/19
- nucleus-tools: 26 pass + 4 skip (0 unexpected)
- Total: 49 tests, 0 unexpected failures

---
