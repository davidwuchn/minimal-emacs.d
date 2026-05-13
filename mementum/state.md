# Mementum State

> Last session: 2026-05-13


## Current Session: AutoTTS + Self-Evolution Integration + Statistical Controller

**Status:** Infrastructure complete (100%). Learning layer implemented (statistical controller). All syntax valid.

**Done (Today):**
- **AutoTTS Integration Complete** — 4 critical gaps filled:
  1. **Reward signal bridge** (`research-benchmark.el:571-614`): `gptel-auto-workflow--update-trace-outcomes` links experiment outcomes to research traces. Hooked into `gptel-auto-experiment-log-tsv`.
  2. **Turn 2 timeout fix** (`strategic.el:768-857`): Returns accumulated findings on timeout instead of failing. Turn 2+ timeout 180s→300s.
  3. **Branching implementation** (`strategic.el:825-838`): Controller supports `stop`, `continue`, `cut`, `branch`. On stagnation, tries alternate strategy.
  4. **Controller enhancement** (`strategic.el:1614-1641`): Content-aware decisions using actual output text.
- **Statistical Controller** (`research-benchmark.el:172-261` + Python script):
  - `learn_controller.py`: Correlation-based learning from trace outcomes
  - Extracts 8 features: output-length, has-urls, has-structure, has-code, source-own, confidence, tokens-used, step-count
  - Calculates mean differences between kept vs discarded traces
  - Fits simple logistic regression model (sigmoid of weighted features)
  - Learns P(kept | features) → used for STOP/BRANCH decisions
  - Falls back to heuristic when < 5 traces with outcomes
- **Mock traces created** (6 traces: 4 kept, 2 discarded) for testing
  - Kept: 3375 chars avg, 100% URLs/structure, 83% confidence
  - Discarded: 650 chars avg, 0% URLs, 20% confidence
  - Learned weights: length=+1.35, URLs=+2.00, confidence=+1.22, tokens=-0.70
- **Pushed to remote** — `6d11c09c` committed, merged
- **BUG FIX: Statistical controller paren structure** (`a1de9bd6`):
  - Added `(require 'json)` to fix `void-function json-read-from-string`
  - Fixed critical paren nesting: `condition-case` error handler was inside `let*` body
  - Fixed topic detection: `downcase` text before regex matching (case-insensitive)
  - Fixed topic model lookup: handle keyword topics (`:performance`, `:nil-safety`) from JSON plist
  - Topic-specific thresholds now correctly drive controller decisions
  - Batch test: SUCCESS (2 topic models: performance, nil-safety)
  - Strategic regression tests: 12/12 pass
  - Byte-compile: clean

**Verification:**
- ✅ Statistical learning produces valid config (6 traces, 4 kept, 67% base rate)
- ✅ Controller switches to statistical method when data available
- ✅ Probabilities calculated: P(kept|good) ≈ 0.99, P(kept|bad) ≈ 0.01
- ✅ Falls back to heuristic when insufficient data
- ✅ All syntax verified via `forward-sexp`

**Pipeline Impact:**
- Controller now LEARNS from data instead of using hardcoded guesses
- Decisions based on P(kept | features) learned from historical outcomes
- Traces with outcomes drive controller evolution
- Statistical model saved to controller.json alongside heuristic params

**Commits:**
- `6d11c09c` — λ Implement statistical controller: learn from trace outcomes
- `c060583f` — ◈ Update INTRO.md: document AutoTTS integration
- `5910a845` — ◈ Update state: AutoTTS integration complete

**Verification (Today):**
- ✅ Batch test: `gptel-auto-workflow--learn-statistical-controller` returns 2 topic models
- ✅ Topic detection: "Performance" → "performance", "Nil safety" → "nil-safety"
- ✅ Topic-specific controller: `[statistical topic:performance]` vs `[statistical topic:nil-safety]`
- ✅ Strategic regression tests: 12/12 pass
- ✅ Byte-compile: no new warnings
- ✅ **Daemon restart complete** — both daemons restarted and new code loaded
- ✅ **Critical fix verified** — `gptel-auto-workflow--build-research-prompt` now defined in both daemons
- ✅ **Controller bug fixed** — `string-match-p` receives text, not length (no more `stringp, 4152`)

**Daemon Restart Notes:**
- Required `unload-feature` + `load-file` to clear cached definitions
- `build-research-prompt` was missing after initial load due to feature caching
- Both daemons now have all 60 defuns from strategic.el

**Next Steps:**
1. **Monitor pipeline** — verify real traces get outcomes populated (mock traces have invalid hashes)
2. **Observe learned weights** — confirm they make sense after ~5 real traces
3. **Measure improvement** — compare research effectiveness statistical vs heuristic

**Pipeline Status:**
- ✅ Daemons restarted and new code loaded
- Cron: `0 23,3,7,11,15,19 * * *`
- Next run: 23:00 (ready)
- Real traces will replace mock traces once pipeline runs with outcome updates
