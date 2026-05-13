# AutoTTS + Self-Evolution Integration Analysis

## Executive Summary

**Current State**: ~65% integrated. Core infrastructure exists and is wired.
**Critical Gap**: Missing reward signal linking research → experiments → evolution.
**Next Priority**: Bridge traces to experiment outcomes for meaningful controller learning.

---

## What Works (Green)

| Component | Status | Evidence |
|-----------|--------|----------|
| Trace collection | ✅ | 3 traces saved, `--save-research-trace` called from `--finalize-research` |
| Step-level logging | ✅ | `--log-research-step`, `--extract-research-steps` parse output |
| Multi-turn controller | ✅ | 3 turns × 180s, STOP/CONTINUE/CUT decisions |
| Controller config | ✅ | `var/tmp/researcher-controller.json` exists with evolved params |
| Confidence scoring | ✅ | Heuristic based on URLs, structure, length |
| Offline benchmark | ✅ | `--offline-benchmark-strategies` scores 4 strategies vs traces |
| Convergence detection | ✅ | 3-gen window, 0.01 threshold, stops overfitting |
| Evolution cycle | ✅ | `--run-autotts-evolution` called from `--evolve-all-skills` |
| Skill update | ✅ | `--update-skill-with-controller` injects config into SKILL.md |
| Knowledge synthesis | ✅ | `--synthesize-research-knowledge` extracts topic performance |

---

## What's Missing (Red)

### 1. Reward Signal — CRITICAL

**AutoTTS**: Traces labeled with outcome (success/failure) from downstream task.
**Us**: Traces save output quality but NOT whether research led to kept experiments.

**Problem**: Controller evolves toward "longer output with URLs" not "research that improves experiments."

**Evidence**: 
- Controller evolved to 95% own-repo priority (based on 2/2 success rate)
- But no trace links to which experiments used those findings
- Topic performance in SKILL.md shows nil-safety 28% success — but this comes from self-evolution, not AutoTTS traces

**Fix**: Add `:experiment-ids` and `:outcome` fields to traces.

### 2. Turn 2 Timeout — CRITICAL

**Problem**: Second turn consistently times out after 180s.
**Evidence**: State.md shows "Turn 2: Times out after 180s (web fetches take too long)"

**Root cause**: 
- Turn 1 uses WebSearch → gets URLs
- Turn 2 tries to WebFetch those URLs → each fetch is slow
- 180s insufficient for multiple fetches

**Fix**: 
- Option A: Increase per-turn timeout to 300s
- Option B: Make turn 2 fetch-only with shorter timeout per fetch
- Option C: Single-turn mode with longer timeout (600s)

### 3. Branching Not Implemented — HIGH

**Controller has 4 decisions**: STOP, CONTINUE, CUT, BRANCH
**Implemented**: STOP, CONTINUE, CUT
**Missing**: BRANCH

**AutoTTS meaning**: BRANCH = try different search strategy in parallel
**Our potential**: BRANCH = switch from "own-repo" to "external" or "topic-specific"

**Fix**: Add branch logic:
```elisp
((eq controller-decision 'branch)
 (message "[autotts] BRANCH: trying alternative strategy")
 ;; Switch strategy and run parallel turn
 (let ((alt-strategy (if (string= strategy "own-repos-first")
                         "deep-external"
                       "own-repos-first")))
   ...))
```

### 4. Controller is Heuristic, Not Learned — MEDIUM

**AutoTTS paper**: Uses decision tree / neural controller trained on traces with RL.
**Us**: Rule-based controller with hand-tuned thresholds.

**Gap**: Cannot discover non-obvious strategies like "stop early on Fridays" or "search arxiv first for performance topics."

**Mitigation**: Our offline benchmark + convergence detection approximates this with grid search.
**Improvement**: Could add simple statistical learning (e.g., "which source works best for topic X?")

### 5. Self-Evolution ↔ AutoTTS Data Silo — MEDIUM

**Self-evolution tracks**: Topic → success rate (from experiments)
**AutoTTS tracks**: Source → success rate (from research traces)

**Gap**: These don't talk to each other.
- Self-evolution knows "nil-safety has 28% success" → should tell AutoTTS to search for nil-safety
- AutoTTS knows "own-repo has 100% success" → should tell self-evolution to prioritize own-repo research

**Fix**: Merge knowledge bases in `--synthesize-research-knowledge`.

### 6. Trace Enrichment — LOW

**Current trace fields**: prompt, output, strategy, confidence, tokens, steps
**Missing**: 
- Which experiments consumed this research
- Time of day (research might work better at certain times)
- Model used (MiniMax vs others)
- Actual cost in dollars

---

## Integration Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  RESEARCH SESSION                                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Turn 1       │→│ Controller   │→│ Turn 2/STOP  │      │
│  │ 180s         │  │ decides      │  │              │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│       ↓ TRACE                                           │
│  ┌────────────────────────────────────────────────────┐  │
│  │ Trace: prompt, output, steps, confidence, tokens   │  │
│  │ Save to var/tmp/research-traces/                   │  │
│  └────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  EXPERIMENT SESSION (hours later)                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Run exp      │→│ Grade        │→│ Keep/discard │      │
│  │ with research│  │ result       │  │              │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│       ↓ UPDATE TRACE OUTCOME                            │
│  ┌────────────────────────────────────────────────────┐  │
│  │ Find trace by hash, add :outcome :kept/:discarded  │  │
│  └────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  EVOLUTION CYCLE (pipeline end)                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ 1. Load traces with outcomes                          │  │
│  │ 2. Evolve controller (prioritize sources that led     │  │
│  │    to kept experiments)                               │  │
│  │ 3. Run offline benchmark                              │  │
│  │ 4. Synthesize: merge topic perf + source perf         │  │
│  │ 5. Update SKILL.md with controller + topics           │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Plan

### Phase 1: Reward Signal Bridge (Critical)
**File**: `gptel-auto-workflow-research-benchmark.el`
**Tasks**:
1. Add `:experiment-ids` to trace structure
2. Add `--update-trace-outcomes` function
3. Call from experiment grading pipeline

### Phase 2: Fix Turn 2 Timeout (Critical)
**File**: `gptel-auto-workflow-strategic.el`
**Tasks**:
1. Detect timeout in `--run-research-turn`
2. Return accumulated findings instead of empty
3. Consider increasing timeout or switching to single-turn

### Phase 3: Implement Branching (High)
**File**: `gptel-auto-workflow-strategic.el`
**Tasks**:
1. Add BRANCH handler in `--run-research-turn`
2. Try alternate strategy on branch
3. Merge results from both branches

### Phase 4: Merge Knowledge Bases (Medium)
**File**: `gptel-auto-workflow-research-benchmark.el`
**Tasks**:
1. Read self-evolution topic performance
2. Feed into `--synthesize-research-knowledge`
3. Update SKILL.md with combined guidance

### Phase 5: Statistical Learning (Low)
**File**: `gptel-auto-workflow-research-benchmark.el`
**Tasks**:
1. Learn "topic → best source" mapping from traces
2. Learn "time of day → success" pattern
3. Inject learned rules into controller

---

## Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Traces with outcomes | 0% | 80% |
| Turn 2 success rate | 0% | 60% |
| Controller decisions/session | 1-2 | 2-3 |
| Research → keep correlation | unknown | >0.3 |
| Offline evolution cycles/run | 1 | 1 |
| Token efficiency | baseline | +30% |

---

## Immediate Actions

1. **Add trace outcome tracking** — most impactful
2. **Fix turn 2 timeout** — unblock multi-turn
3. **Test end-to-end** — verify evolution produces better controller
4. **Monitor** — check if research effectiveness improves

---

*Analysis date: 2026-05-13*
*Analyst: ψ (AI assistant)*
