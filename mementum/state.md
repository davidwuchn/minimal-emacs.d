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

---

## AutoTTS + Self-Evolution Integration (Completed `11f21b1c`)

**Integration Status:** Phases 1-4 complete. Researcher and controller now share data.

### Phase 1 ✅: Outcome Linking (Already Worked)
- `update-trace-outcomes` already hooked into experiment logging
- Traces now have `:outcomes` array with experiment results
- 12 traces with outcomes (8 kept, 4 discarded, 66.7% base rate)

### Phase 2 ✅: Dynamic Researcher Skill (`evolution.el`)
- **Helper functions:** `generate-source-effectiveness-section`, `generate-controller-guidance-section`, `generate-dynamic-instructions`
- **RESEARCHER.md now includes:**
  - Source effectiveness table (own-repo vs external with keep rates)
  - Controller guidance (thresholds, budget, priorities, topic models)
  - Dynamic instructions that adapt based on trace outcomes
  - Source strategy recommendations (e.g., "PRIORITY: Search davidwuchn/* repos FIRST")

### Phase 3 ✅: Controller Uses Self-Evolution Data (`strategic.el`)
- `get-self-evolution-topic-rate` — reads experiment TSVs for topic keep rate
- `adjust-thresholds-for-topic` — adjusts stop/branch thresholds based on topic performance
- High keep rate → lower stop threshold (keep researching)
- Low keep rate → raise stop threshold (stop early)

### Phase 4 ✅: Unified Evolution Hook (`evolution.el`)
- `evolve-all-skills` now calls `evolve-researcher-skill` before feedback analysis
- Single cycle: synthesize → consolidate → evolve skills → evolve researcher → AutoTTS strategy evolution

### Phase 5 🔄: Adaptive Prompts (Future)
- Inject controller decision into research prompt per turn
- Requires modifying `run-research-turn` to pass decision to prompt builder

### Test Results
- Batch test: 2 topic models (performance: 60% base, nil-safety: 80% base)
- Controller decision: STOP with topic-specific model for nil-safety
- Threshold adjustment: stop=0.70, branch=0.30 (no self-evolution data yet for nil-safety)
- Researcher evolution: generates dynamic RESEARCHER.md with source effectiveness

---

## Sync Review: Remote Optimization Experiments (Merged `0e4b6f4f`)

**Resolved:** Conflict in `token-efficiency.md` — took newest data (18544 chars, 119/748 experiments)
**Migrated:** `token-efficiency.md` moved from `assistant/skills/auto-workflow/` to `mementum/knowledge/` (learned data, not a skill)

**Incoming Changes (from remote optimize/* branches):**

1. **New strategy:** `strategy-semantic-compression.el` (62 lines)
   - Compresses function bodies to `...` while preserving signatures
   - Targets: `defun`, `defmacro`, `cl-defun`, `defadvice`
   - Hypothesis: Preserve interfaces, reduce tokens

2. **`gptel-agent-loop.el`** — Defensive guards
   - `continuation-prompt-for`: Validates task structure before processing
   - `compile-patterns`: Uses `proper-list-p` instead of `listp`

3. **`gptel-ext-context.el`** — Proper list validation
   - `extract-last-task`: Guards against non-list input

4. **`gptel-ext-fsm-utils.el`** — FSM robustness
   - Nil callback defaults to `#'ignore`
   - Pre-compiled FSM ID regex for O(1) matching

5. **`gptel-ext-retry.el`** — Message validation
   - Truncation: Checks `proper-list-p msg` before `plist-get`

6. **`gptel-benchmark-core.el`** — plist validation
   - `plist-to-alist`: Uses `proper-list-p` guard

**Pattern:** Remote experiments focused on **nil-safety hardening** — adding `proper-list-p` guards across multiple modules. This aligns with our nil-safety topic model (weight +2.0 for `source_own`).

**Sync Status:** ✅ Local + remote merged, pushed to `4cc93e30`
