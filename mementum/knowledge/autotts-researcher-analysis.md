---
title: AutoTTS vs Our Researcher - Gap Analysis & Integration Plan
status: active
category: research
tags: [autotts, researcher, self-evolution, integration]
related: [autotts-firethering-article, researcher-skill-v2]
depends-on: []
---

# AutoTTS vs Our Researcher: Deep Analysis

## AutoTTS Overview

AutoTTS (Automated Test-Time Scaling) is a framework where an AI agent automatically discovers optimal inference strategies through:

1. **Offline Replay Environment:** Pre-collect reasoning traces, chunk into segments, cache probe responses
2. **Controller Synthesis:** Agent writes Python controller code that decides: BRANCH / CONTINUE / PROBE / PRUNE / STOP
3. **Cheap Evaluation:** Test controllers against replay store (0 LLM calls, ~160 min, $39.90)
4. **Iterative Refinement:** Agent gets accuracy + token cost + execution traces, rewrites controller
5. **Discovered Strategy:** Confidence Momentum Controller (CMC) - uses EMA of confidence with trend analysis

### Key Innovation: Beta Parameterization
All hyperparameters are deterministic functions of a single scalar β ∈ [0,1]:
- β=0: Conservative (few branches, easy to stop)
- β=1: Aggressive (many branches, hard to stop)
- This eliminates brittle threshold tuning

### CMC Core Mechanisms:
1. **EMA Momentum Gate:** Stops only when confidence is high AND trend is non-negative
2. **Trend-Based Widening:** Opens new branches when confidence stagnates
3. **Probe-Age Priority:** Concentrates compute on branches closest to completion
4. **Three-Tier Classification:** aligned / neutral / deviant branches
5. **Conservative Abandonment:** Only cuts after persistent deviation, keeps ≥2 alive

---

## Our Current Researcher System

### What We Have:
1. **Multi-turn research** with controller checkpoints after each turn
2. **Controller decisions:** STOP / CONTINUE / BRANCH / CUT / TIMEOUT
3. **Adaptive prompts:** Injects CONTINUE/BRANCH guidance based on previous decision
4. **Global state variables:** Avoids closure issues in daemon
5. **Statistical learning:** Learns from trace outcomes (kept vs discarded)
6. **Source effectiveness tracking:** Own repos vs external sources
7. **Topic models:** Performance per research topic (performance, nil-safety, etc.)

### Current Controller Logic (simplified):
```
Heuristic path (insufficient data):
  - STOP if output > 3000 chars OR has URLs + structure
  - BRANCH if output < 1000 chars AND tokens > 2000 (BUG: mutually exclusive)
  - CONTINUE otherwise

Statistical path (≥6 traces):
  - Uses logistic regression on features: output-length, has-urls, source-type
  - P(kept | features) learned from historical outcomes
```

### Current Research Prompt:
- 153 lines of instructions
- Source strategy (own-repos-first at 95% priority)
- Static controller guidance (hardcoded thresholds)
- Manual source monitoring (lists 30+ repos)
- Anti-patterns listed explicitly

---

## Gap Analysis: What AutoTTS Has That We Don't

### 1. **Replay Environment for Research** ⚠️ CRITICAL
**AutoTTS:** Pre-collects reasoning traces, chunks into segments, creates replay store
**Us:** No replay store. Every research turn makes live LLM calls.
**Impact:** We can't cheaply evaluate research strategies. Each evaluation costs actual API calls.

**Gap Severity:** HIGH
**Solution:** Build research trace replay system

### 2. **Beta Parameterization** ⚠️ CRITICAL
**AutoTTS:** Single β scalar controls all hyperparameters deterministically
**Us:** Hardcoded thresholds (stop: 0.65, token budget: 8000, own-repo priority: 95%)
**Impact:** Can't smoothly trade off exploration vs exploitation. Manual tuning required.

**Gap Severity:** HIGH
**Solution:** Implement β parameterization for research controller

### 3. **EMA Momentum-Based Confidence** ⚠️ HIGH
**AutoTTS:** Uses exponential moving average of confidence with trend analysis
**Us:** Single-turn confidence estimation (length-based heuristic or statistical model)
**Impact:** We stop on transient spikes. No memory of confidence trends across turns.

**Gap Severity:** HIGH
**Solution:** Add EMA confidence tracking across research turns

### 4. **Probe-Age Priority Scheduling** ⚠️ MEDIUM
**AutoTTS:** Allocates compute to branches based on probe count (seniority)
**Us:** Uniform treatment of all sources/topics
**Impact:** Not concentrating research effort on promising directions

**Gap Severity:** MEDIUM
**Solution:** Weight sources by historical effectiveness

### 5. **Three-Tier Branch Classification** ⚠️ MEDIUM
**AutoTTS:** aligned / neutral / deviant classification per branch
**Us:** Binary kept/discarded at experiment level only
**Impact:** Can't adapt research depth based on source alignment with consensus

**Gap Severity:** MEDIUM
**Solution:** Classify sources by agreement with findings

### 6. **Trend-Based Widening** ⚠️ HIGH
**AutoTTS:** Opens new branches when EMA delta ≤ threshold (confidence stagnation)
**Us:** Static max-turns (3-5 turns) or heuristic BRANCH trigger
**Impact:** We don't dynamically expand research when current approach isn't working

**Gap Severity:** HIGH
**Solution:** Link branching decision to confidence trend, not just turn count

### 7. **Execution Trace Feedback** ⚠️ CRITICAL
**AutoTTS:** Agent gets full action-by-action traces showing where controller succeeded/failed
**Us:** Only get final outcome (kept/discarded) + summary stats
**Impact:** Agent can't diagnose WHY research strategy failed

**Gap Severity:** CRITICAL
**Solution:** Capture detailed execution traces per research turn

### 8. **Controller Code as Search Space** ⚠️ HIGH
**AutoTTS:** Agent literally writes Python controller class, code is the search space
**Us:** Controller is hardcoded Elisp function with some learned parameters
**Impact:** Limited expressiveness. Can't discover fundamentally new strategies.

**Gap Severity:** HIGH
**Solution:** Make controller programmable (e.g., load from skill file)

### 9. **Cheap Offline Evaluation** ⚠️ CRITICAL
**AutoTTS:** Evaluation costs 0 LLM calls (replays cached traces)
**Us:** Every experiment costs actual LLM inference
**Impact:** Can't afford to iterate research strategies hundreds of times

**Gap Severity:** CRITICAL
**Solution:** Build research trace cache and replay system

### 10. **Held-Out Validation** ⚠️ MEDIUM
**AutoTTS:** Discovers on AIME24, validates on AIME25 + HMMT25
**Us:** No explicit train/validation split for research strategies
**Impact:** May overfit to specific problem types

**Gap Severity:** MEDIUM
**Solution:** Split experiments into train/validation sets

---

## Integration Architecture

### Phase 1: Research Trace Replay Store (Foundation)
```
research-traces/
├── raw/                    # Full research turn outputs
├── chunked/               # Segmented by topic/source
├── probes/               # Pre-computed quality signals
└── replay-index.json     # Fast lookup table
```

**Benefits:**
- Evaluate research strategies without API calls
- Compare controller A vs B on same traces
- Build training data for statistical models

### Phase 2: Beta Parameterization
```elisp
(defun gptel-auto-workflow--research-beta-schedule (beta)
  "Return parameter dict for research controller."
  (list
   :max-turns (max 2 (round (+ 2 (* 6 beta))))
   :stop-threshold (+ 0.65 (* 0.12 beta))
   :token-budget (+ 4000 (* 8000 beta))
   :own-repo-priority (+ 0.5 (* 0.45 beta))
   :ema-alpha (- 0.70 (* 0.40 beta))
   :branch-patience (max 2 (round (+ 2 (* 8 beta))))
   :widen-burst (max 1 (round (+ 1 (* 3 beta))))
   :trend-threshold (- 0.04 (* 0.03 beta))))
```

### Phase 3: EMA Confidence Tracking
```elisp
(defvar gptel-auto-workflow--research-ema-conf 0.0)
(defvar gptel-auto-workflow--research-ema-history '())

(defun gptel-auto-workflow--update-research-ema (new-confidence)
  "Update EMA with new confidence reading."
  (let ((alpha gptel-auto-workflow--research-ema-alpha))
    (setq gptel-auto-workflow--research-ema-conf
          (+ (* (- 1 alpha) gptel-auto-workflow--research-ema-conf)
             (* alpha new-confidence)))
    (push gptel-auto-workflow--research-ema-conf 
          gptel-auto-workflow--research-ema-history)
    (when (> (length gptel-auto-workflow--research-ema-history) 
             gptel-auto-workflow--research-ema-window)
      (setq gptel-auto-workflow--research-ema-history
            (butlast gptel-auto-workflow--research-ema-history)))))
```

### Phase 4: Source Classification (aligned/neutral/deviant)
```elisp
(defun gptel-auto-workflow--classify-source (source findings)
  "Classify source based on agreement with current findings."
  (let ((consensus (gptel-auto-workflow--extract-consensus findings)))
    (cond
     ;; Source produced findings that match consensus
     ((gptel-auto-workflow--source-agrees-p source consensus)
      'aligned)
     ;; Source contradicts or produces low-quality output
     ((gptel-auto-workflow--source-deviant-p source consensus)
      'deviant)
     ;; No clear signal yet
     (t 'neutral))))
```

### Phase 5: Trend-Based Widening
```elisp
(defun gptel-auto-workflow--should-widen-research (ema-delta)
  "Return non-nil if we should open new research branches."
  (and (< ema-delta gptel-auto-workflow--research-trend-threshold)
       (> gptel-auto-workflow--research-total-turns 
          (/ gptel-auto-workflow--research-warm-up 2))
       (< gptel-auto-workflow--research-ema-conf 
          gptel-auto-workflow--research-stop-threshold)))
```

### Phase 6: Execution Trace Recording
```elisp
(defun gptel-auto-workflow--record-research-trace (turn data)
  "Record detailed trace of research turn for feedback."
  (push (list :turn turn
              :timestamp (current-time)
              :controller-decision (plist-get data :decision)
              :confidence (plist-get data :confidence)
              :ema-conf (plist-get data :ema-conf)
              :ema-delta (plist-get data :ema-delta)
              :source-effectiveness (plist-get data :source-effectiveness)
              :output-length (plist-get data :output-length)
              :tokens-used (plist-get data :tokens-used)
              :findings-quality (plist-get data :findings-quality))
        gptel-auto-workflow--research-trace-log))
```

---

## Implementation Priority

### Immediate (This Week)
1. **Fix heuristic BRANCH bug** - dead code with mutually exclusive conditions
2. **Add EMA confidence tracking** - track across turns, not just per-turn
3. **Implement beta parameterization** - single scalar controls all thresholds

### Short Term (Next 2 Weeks)
4. **Build trace replay cache** - cache research outputs for cheap evaluation
5. **Add source classification** - aligned/neutral/deviant per source
6. **Record execution traces** - detailed per-turn diagnostics

### Medium Term (Next Month)
7. **Controller as skill** - make controller programmable from skill file
8. **Held-out validation** - split experiments into train/validation
9. **Cross-run learning** - share learned parameters across daemon restarts

---

## Expected Impact

### Without AutoTTS Integration
- Research effectiveness: 0-15% (current)
- Token waste: ~60% on unproductive turns
- Strategy tuning: Manual, sporadic

### With AutoTTS Integration
- Research effectiveness: 40-60% (projected)
- Token waste: ~20% (70% reduction like AutoTTS)
- Strategy tuning: Automated, continuous
- Discovery cost: $0 (replay-based evaluation)

---

## Open Questions

1. **Replay Store Size:** How many research traces needed for effective replay? (AutoTTS: thousands)
2. **Chunking Strategy:** AutoTTS chunks by token segments. We chunk by... turns? sources? topics?
3. **Probe Definition:** AutoTTS probes = reveal partial answer. Our probes = ?
4. **Generalization:** AutoTTS transfers across benchmarks. Can our controller transfer across project types?
5. **Agent Access:** AutoTTS uses Claude Code agent. Should we use our own agent pipeline?

---

## Next Actions

1. [ ] Implement EMA confidence tracking in `strategic-daemon-functions.el`
2. [ ] Add beta parameterization to controller
3. [ ] Create research trace cache structure
4. [ ] Record execution traces per turn
5. [ ] Design replay evaluation pipeline
6. [ ] Test on held-out experiments

*Analysis based on: AutoTTS paper (arXiv:2605.08083), GitHub repo (zhengkid/AutoTTS), and Firethering article (2026-05-12)*
