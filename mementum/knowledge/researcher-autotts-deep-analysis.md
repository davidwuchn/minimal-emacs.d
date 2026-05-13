# Deep Analysis: Researcher vs AutoTTS — Integration Plan

## Current State Assessment

### What We Have (Working)
1. **Researcher SKILL.md** — Prompt template with AutoTTS concepts (v2.1)
2. **Research findings flow** — Research output → `var/tmp/research-findings.md` → analyzer/executor
3. **Benchmark module** — `gptel-auto-workflow-research-benchmark.el` (just committed, not wired)
4. **AutoTTS Python scripts** — Controller + evolution scripts (standalone, not called)
5. **Trace directory** — `var/tmp/research-traces/` exists but mostly empty
6. **Replay store** — `var/tmp/research-replay-store.json` exists but empty

### What AutoTTS Actually Does
**AutoTTS** = Test-Time Scaling via Controller Discovery
- **Phase 1**: Collect reasoning traces (every branch, every step)
- **Phase 2**: Write controller code → test offline against traces → iterate
- **Phase 3**: Deploy controller for 70% token reduction

**Key insight**: After trace collection, NO MORE LLM CALLS needed for evaluation.

## Gap Analysis (Detailed)

### Gap 1: NO Trace Collection ⚠️ CRITICAL
**AutoTTS**: Saves every reasoning step with full context
```python
trace = {
  "query": "site:github.com/davidwuchn gptel",
  "tool": "WebSearch",
  "response": {...},
  "tokens": 450,
  "confidence_before": 0.3,
  "confidence_after": 0.7,
  "timestamp": "..."
}
```

**Us**: We save prompt + final output only
**Location**: `gptel-tools-agent-prompt-build.el:530` loads findings, but no trace saved
**Impact**: Cannot replay, analyze, or evolve strategies

### Gap 2: NO Controller Interface ⚠️ CRITICAL
**AutoTTS**: Controller is executable Python code with clear decisions
```python
def controller(state):
    if state.confidence > 0.7: return STOP
    if state.confidence_stagnant(window=3): return BRANCH
    return CONTINUE
```

**Us**: "Strategy" is text in markdown. No executable interface.
**Location**: `researcher-prompt/SKILL.md` mentions controller but it's NOT code
**Impact**: Cannot programmatically test, compare, or evolve strategies

### Gap 3: NO Offline Evaluation ⚠️ CRITICAL
**AutoTTS**: Test controller against replay store = 0 LLM calls
**Us**: To test a strategy, must run full pipeline ($$$ + minutes)
**Location**: Benchmark module exists but not called from anywhere
**Impact**: Cannot iterate quickly

### Gap 4: NO Confidence Metrics
**AutoTTS**: Tracks confidence at every step
**Us**: No confidence tracking at all
**Impact**: Controller has no signal to make decisions

### Gap 5: NO Cost Attribution
**AutoTTS**: Measures tokens per trace, per decision
**Us**: Don't know which searches cost what
**Impact**: Cannot optimize cost-effectiveness

### Gap 6: NO Integration Between AutoTTS and Self-Evolution
**AutoTTS** optimizes HOW to research
**Self-Evolution** optimizes WHAT to research
**Current state**: Completely separate systems

## Root Cause

The fundamental issue: **We built the PROMPT to talk about AutoTTS, but built ZERO of the MECHANICS.**

- We have a controller.py script sitting in scripts/ — never called
- We have a benchmark.el module — not wired to pipeline
- We have evolution.py — not wired to pipeline
- We have trace directory — no traces written there
- We have replay store file — empty

**We're at ~5% capability because only the CONCEPT exists in the prompt, not the IMPLEMENTATION.**

## Integration Architecture (Refined Option C)

### Layer Stack

```
┌─────────────────────────────────────────────────────────────┐
│  RESEARCH SESSION (happens now)                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   SEARCH     │→│   FETCH      │→│ SYNTHESIZE   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│       ↓ TRACE        ↓ TRACE          ↓ TRACE              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  TRACE COLLECTOR (new — saves every step)                    │
│  - query, response, tokens, confidence, timestamp           │
│  - saves to var/tmp/research-traces/YYYY-MM-DD-HHMMSS.json  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  PIPELINE COMPLETES → EVOLUTION HOOK                         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  AutoTTS Layer (HOW to research)                      │  │
│  │  - Load traces                                        │  │
│  │  - Evaluate strategies offline (benchmark module)     │  │
│  │  - Evolve controller parameters                       │  │
│  │  - Save to researcher-controller.json                 │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Self-Evolution Layer (WHAT to research)              │  │
│  │  - Parse experiment results                           │  │
│  │  - Update topic performance                           │  │
│  │  - Update source effectiveness                        │  │
│  │  - Save to SKILL.md                                   │  │
│  └──────────────────────────────────────────────────────┘  │
│                            ↓                                │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  MERGE LAYER (integration point)                      │  │
│  │  - Controller config → strategy guidance in SKILL.md  │  │
│  │  - Knowledge → topic priorities in SKILL.md           │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  NEXT RESEARCH SESSION                                       │
│  - Loads evolved controller config from JSON                 │
│  - Uses updated topic priorities from SKILL.md               │
│  - Makes better decisions, uses fewer tokens                 │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Research happens** → traces saved
2. **Pipeline ends** → `--evolve-all-skills` hook runs
3. **Hook calls**: benchmark-based strategy evolution
4. **Hook calls**: self-evolution knowledge synthesis
5. **Hook merges**: controller + knowledge → SKILL.md
6. **Next run**: Researcher loads evolved guidance

## Implementation Plan

### Phase 1: Trace Collection (Critical — Do First)
**File**: `gptel-auto-workflow-research-tracer.el`
**What**: Hook into `gptel-benchmark-call-subagent` to save every tool call
**Output**: `var/tmp/research-traces/YYYY-MM-DD-HHMMSS.json`

### Phase 2: Controller Integration (Critical)
**File**: Modify `gptel-auto-workflow-strategic.el`
**What**: Before calling researcher, load controller config. After researcher returns, evaluate decisions.
**Output**: Controller makes actual decisions (search own repos? stop early?)

### Phase 3: Benchmark Wiring (High)
**File**: `gptel-auto-workflow-evolution.el`
**What**: In `--evolve-all-skills`, call benchmark module to test strategies offline
**Output**: Best strategy saved to `researcher-controller.json`

### Phase 4: Smooth Merge (Medium)
**File**: `assistant/skills/researcher-prompt/SKILL.md`
**What**: Actually inject controller config and knowledge into prompt
**Output**: Dynamic prompt with evolved parameters

### Phase 5: Confidence Scoring (Medium)
**File**: Enhance tracer + controller
**What**: Extract confidence signals from researcher output (has URLs? structured? long?)
**Output**: Confidence metrics per step

## Key Design Decisions

1. **Controller lives in Elisp, not Python** — We already have benchmark infrastructure in Elisp. Python scripts are standalone and not integrated. Better to build controller logic in Elisp that can call the Python scripts if needed.

2. **Traces are JSON, not SEXP** — Easier to process with existing Python scripts, interoperable.

3. **Offline evaluation uses benchmark module** — We already built it. Wire it in.

4. **Hook runs after pipeline, not during** — Don't slow down research. Evolve offline.

5. **SKILL.md gets controller params injected** — The researcher prompt should include actual numbers (stop threshold, priorities) not just concepts.

## Next Actions

1. **Write trace collector** — Hook into the actual research call point
2. **Wire benchmark module** — Call it from `--evolve-all-skills`
3. **Inject controller params** — Make SKILL.md dynamic
4. **Test end-to-end** — Verify traces → evolution → better research

## Success Metrics

- **Traces collected**: ≥1 per research session
- **Controller decisions**: ≥1 per session (stop early, branch, etc.)
- **Token reduction**: Target 30% fewer tokens per insight
- **Keep rate improvement**: Target 20% → 25% research effectiveness
- **Offline evolution cycles**: ≥1 per pipeline run

---

*Analysis completed. Ready to implement.*
