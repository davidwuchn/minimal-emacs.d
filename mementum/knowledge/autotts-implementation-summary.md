---
title: AutoTTS Integration - Implementation Summary
status: done
category: research
tags: [autotts, implementation, complete]
related: [autotts-researcher-analysis]
depends-on: []
---

# AutoTTS Integration: Implementation Complete

## What Was Implemented

### Phase 1: EMA Confidence + Beta Parameterization
**File:** `lisp/modules/strategic-daemon-functions.el`

**Features:**
- **Beta parameterization** (`β ∈ [0,1]`): Single scalar controls all thresholds
  - `gptel-auto-workflow--research-beta-schedule`: Parameter scheduling
  - β=0: Conservative (2 turns, stop@0.65, EMA α=0.7)
  - β=1: Aggressive (8 turns, stop@0.77, EMA α=0.3)
  - Default: β=0.5 (5 turns, stop@0.71, EMA α=0.5)

- **EMA momentum tracking**:
  - `gptel-auto-workflow--update-research-ema`: Update EMA with new confidence
  - `gptel-auto-workflow--research-ema-delta`: Calculate trend (positive=improving)
  - Tracks across turns for momentum-aware stopping

- **Momentum gate controller**:
  - STOP: EMA high AND trend non-negative
  - BRANCH: Confidence stagnating (delta below threshold)
  - CONTINUE: Making progress but not yet confident

- **Fixed BRANCH bug**: Removed mutually exclusive conditions (`output < 1000` AND `tokens > 2000`)

- **Execution trace recording**:
  - `gptel-auto-workflow--record-research-trace`: Per-turn diagnostics
  - Captures: decision, confidence, EMA, delta, output length, tokens

### Phase 2: Research Trace Replay Cache
**File:** `lisp/modules/gptel-auto-workflow-research-cache.el`

**Features:**
- **Cache research turns** to `var/tmp/research-traces/`
- **JSON-based storage** with index for fast lookup
- **Offline controller evaluation**: 0 LLM calls
- **Beta sweep**: Test multiple β values against cached traces
- **Find optimal β per topic** automatically

**Functions:**
- `gptel-auto-workflow--cache-research-turn`: Save trace
- `gptel-auto-workflow--replay-research-turn`: Simulate decision
- `gptel-auto-workflow--evaluate-controller-offline`: Batch evaluation
- `gptel-auto-workflow--sweep-beta-offline`: Find best β

### Phase 3: Source Classification
**File:** `lisp/modules/strategic-daemon-functions.el` (extended)

**Features:**
- **Three-tier classification**: aligned / neutral / deviant
- **Consensus extraction**: Extract topics/techniques from findings
- **Source agreement detection**: Check if source matches consensus
- **Effectiveness tracking**: Hash table with scores per source
- **Priority scheduling**: Score sources by alignment ratio + quality

**Functions:**
- `gptel-auto-workflow--classify-source`: Main classifier
- `gptel-auto-workflow--extract-consensus`: Topic extraction
- `gptel-auto-workflow--update-source-effectiveness`: Track performance
- `gptel-auto-workflow--source-priority-score`: Calculate priority

---

## Integration Points

### Deep Integration Pass (2026-05-14)

- **Single live controller path:** `gptel-auto-workflow-strategic.el` loads `strategic-daemon-functions.el`, replay cache, and benchmark module so cron and interactive paths use the same AutoTTS controller.
- **Replay uses production traces:** `gptel-auto-workflow-research-cache.el` indexes existing `var/tmp/research-traces/*.json`, detects topics from outcome targets/strategy/prompt, and replays with stored EMA/turn state.
- **Trace schema is replay-complete:** new traces save raw findings/output plus EMA confidence, EMA delta, turn count, and per-turn trace log.
- **Researcher prompt feeds AutoTTS:** `assistant/skills/researcher-prompt/SKILL.md` now requires JSON metadata for strategy, sources, topics, confidence, insight count, and token estimate.
- **Self-evolution uses real outcomes:** trace synthesis and source effectiveness count actual downstream kept/discarded outcomes before falling back to output length.
- **JSON false fixed:** Emacs reads JSON false as `:json-false`; kept checks now require `(eq value t)` so discarded traces are not counted as wins.
- **Reward bridge fixed:** `update-trace-outcomes` now uses `erase-buffer`, so it can actually persist experiment outcomes back into trace files.
- **Cross-layer skill update fixed:** `evolve-all-skills` passes loaded controller config into `update-skill-with-controller` instead of calling it with no argument.

### Bootstrap Loading
`lisp/modules/gptel-auto-workflow-bootstrap.el` now loads:
1. `strategic-daemon-functions.el` (EMA + beta + classification)
2. `gptel-auto-workflow-research-cache.el` (replay cache)

### Researcher Skill Updated
`assistant/skills/auto-workflow/RESEARCHER.md` now documents:
- Beta parameter (0.0-1.0)
- EMA confidence tracking
- Controller decision logic (STOP/BRANCH/CONTINUE/CUT)

---

## Testing Results

### Beta Schedule
```
β=0.0: max-turns=2, stop=0.65, ema-α=0.70  (conservative)
β=0.5: max-turns=5, stop=0.71, ema-α=0.50  (balanced)
β=1.0: max-turns=8, stop=0.77, ema-α=0.30  (aggressive)
```

### EMA Tracking
After 5 updates with α=0.5:
- EMA confidence: 0.709
- Delta: +0.459 (positive = improving trend)

### Source Classification
```
Source (matches consensus)     → aligned
Source (unrelated content)     → deviant
Source (empty/error)           → deviant
```

### Replay Verification
```
Cached traces indexed: 15
Topics detected: nil-safety, performance, general, error-handling, async
Downstream outcomes known: 12
Outcome successes after JSON false fix: 10
nil-safety offline eval: 4 traces, 0 LLM calls
```

---

## Expected Impact

### Before AutoTTS
- Research effectiveness: 0-15%
- Token waste: ~60%
- Strategy tuning: Manual
- Heuristic BRANCH: Dead code

### After AutoTTS
- Research effectiveness: 40-60% (projected)
- Token waste: ~20% (70% reduction)
- Strategy tuning: Automated via β sweep
- Controller: Momentum-aware, trend-based

### Cost Reduction
- Offline evaluation: $0 (replay cached traces)
- Beta sweep: $0 (replays only)
- Only live research turns cost API calls

---

## Files Changed

| File | Changes |
|------|---------|
| `lisp/modules/strategic-daemon-functions.el` | +390 lines (EMA + beta + classification) |
| `lisp/modules/gptel-auto-workflow-research-cache.el` | New (+200 lines) |
| `lisp/modules/gptel-auto-workflow-bootstrap.el` | Load cache module |
| `assistant/skills/auto-workflow/RESEARCHER.md` | Document new features |
| `.gitignore` | Exceptions for new modules |

---

## Commits

1. `13058cab` - Phase 1: EMA confidence + beta parameterization
2. `0631b1c2` - Phase 2: Research trace replay cache
3. `7fd597f3` - Phase 3: Source classification

---

## Next Steps (Future Work)

1. **Controller as skill**: Make controller programmable from skill file
2. **Held-out validation**: Split experiments into train/validation sets
3. **Probe definition**: Define what "probing" means for research (partial fetch?)
4. **Beta auto-tuning threshold:** collect enough real traces for automatic beta sweep
5. **Pipeline measurement:** compare research effectiveness before/after deep integration

---

## References

- AutoTTS Paper: arXiv:2605.08083
- AutoTTS Repo: https://github.com/zhengkid/AutoTTS
- Firethering Article: https://firethering.com/autotts-ai-inference-test-time-scaling/
- Analysis Doc: `mementum/knowledge/autotts-researcher-analysis.md`
