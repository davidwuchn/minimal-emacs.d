# AutoTTS Integration: Post-Implementation Gap Analysis

## Status After Recent Changes

**Implemented:**
- ✅ Trace collection with step-level logging
- ✅ Reward signal bridge (outcomes linked to traces)
- ✅ Multi-turn controller with 4 decisions
- ✅ Timeout fix for turn 2+
- ✅ Offline benchmark (0 LLM calls)
- ✅ Convergence detection
- ✅ Hooked into evolution cycle

**Not working yet:**
- ❌ Outcomes not populated in traces (no experiments ran since implementation)
- ❌ Controller is rule-based heuristic, not learned from data
- ❌ No intermediate reasoning traces (only final output saved)
- ❌ Self-evolution and AutoTTS data silos persist

---

## Deep Gap Analysis

### Gap 1: Controller is Heuristic, Not Learned (CRITICAL)

**AutoTTS paper:** Uses supervised learning on traces to train a controller (decision tree or neural net) that predicts whether to STOP/CONTINUE based on features.

**Our implementation:** Hardcoded rules:
```elisp
((> output-length 2000) (has-urls) (>= insights-count 2)) → 'stop
((< output-length 1000) (no-urls) (> tokens-used 2000)) → 'branch
```

**Problem:** These rules are hand-tuned guesses. They don't adapt to:
- Which features actually predict experiment success
- Topic-specific patterns (e.g., "async" research needs different thresholds than "nil-safety")
- Time-of-day or model-specific effects
- Historical correlation between confidence and outcomes

**Evidence:** Controller evolved to 95% own-repo priority based on 2/2 success rate. With n=2, this is meaningless overfitting.

**Fix needed:** Add simple statistical learning layer:
1. From traces with outcomes, learn P(kept | feature_vector)
2. Use logistic regression or decision tree on features: output-length, has-urls, has-structure, source, topic, model, time-of-day
3. Replace hardcoded thresholds with learned probabilities
4. Update controller.json with learned parameters

### Gap 2: Missing Intermediate Reasoning Traces (HIGH)

**AutoTTS paper:** Saves EVERY tool call with full context:
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

**Our implementation:** Only saves final prompt + output. Step extraction is regex-based:
```elisp
;; Extract WebSearch queries (look for search patterns)
(string-match "\\(?:WebSearch|Search|Query\\)[^:]*:?\\s-*\\(\\(?:[^\n]*\\(?:github|arxiv|reddit|stackoverflow|huggingface\\\\)|[^\n]+\\)\\)" output)
```

**Problem:** 
- Regex fails if output format changes
- Can't distinguish between "searched for X" and "found Y"
- No token counts per step
- No confidence evolution within a turn
- Can't replay individual steps for offline evaluation

**Evidence:** Step extraction is best-effort and often returns 0 steps.

**Fix needed:** Instrument subagent to log actual tool calls:
1. Patch `gptel-benchmark-call-subagent` or instrument tools
2. Save each WebSearch/WebFetch/Read with inputs and outputs
3. Include token estimates per step
4. Save in structured format, not regex-extracted

### Gap 3: Outcomes Not Populated (HIGH)

**Current state:** 3 trace files, all mock data from 10:31 AM. No `:outcomes` array.

**Expected:** After pipeline runs, traces should have:
```json
{
  "outcomes": [
    {"target": "lisp/modules/gptel-agent-loop.el", "kept": true, "score-after": 0.85, "timestamp": "..."},
    {"target": "lisp/modules/gptel-sandbox.el", "kept": false, "score-after": 0.0, "timestamp": "..."}
  ]
}
```

**Problem:** 
- No experiments have run since implementation
- Even when they do, `update-trace-outcomes` only updates by hash match
- Hash is SHA1 of raw findings - if findings change slightly, hash won't match
- No fallback matching (e.g., by timestamp or strategy)

**Fix needed:**
1. Add `:experiment-ids` to trace at creation time
2. In experiment core, pass trace-id alongside research-hash
3. Use timestamp window matching as fallback
4. Log when outcome update succeeds/fails

### Gap 4: Self-Evolution ↔ AutoTTS Data Silo (MEDIUM)

**Self-evolution tracks:**
- Topic → success rate (from experiments)
- Source → effectiveness (from research)

**AutoTTS tracks:**
- Source → success rate (from traces)
- Strategy → efficiency (from offline benchmark)

**Gap:** These don't inform each other.

Example:
- Self-evolution knows "nil-safety has 28% success" → should prioritize nil-safety research
- AutoTTS knows "own-repo has 100% success" → should search own repos more
- But: Self-evolution doesn't tell researcher to focus on nil-safety
- And: AutoTTS doesn't tell self-evolution that own-repo research works best

**Fix needed:** Merge knowledge bases in `--synthesize-research-knowledge`:
1. Read topic-performance.json (self-evolution)
2. Read controller-evolution-history.json (AutoTTS)
3. Cross-reference: which topics benefit most from which sources
4. Update SKILL.md with combined guidance
5. Update controller config with topic-specific source priorities

### Gap 5: Controller Can't Learn Topic-Specific Patterns (MEDIUM)

**Current controller:** One global config for all research.

**AutoTTS potential:** Different topics need different strategies.
- "performance" → needs external sources (benchmarks, papers)
- "nil-safety" → needs own-repo analysis (defensive patterns in our code)
- "error-handling" → needs both (external patterns + internal audit)

**Fix needed:** Topic-aware controller:
1. Learn P(kept | source, topic) from traces
2. Adjust source priorities per topic
3. Controller consults topic before deciding search strategy

### Gap 6: No Cost Attribution (LOW)

**AutoTTS:** Measures tokens per trace, per decision, per insight.

**Us:** Estimated tokens = output-length / 4. No actual API cost tracking.

**Impact:** Can't optimize cost-effectiveness. Can't answer "which research strategy gives most insights per dollar?"

**Fix needed:** Add cost tracking:
1. Log actual API calls with model, input tokens, output tokens
2. Calculate cost per insight
3. Include cost in offline benchmark scoring

---

## Root Cause

We built the **infrastructure** for AutoTTS but not the **learning**.

- ✅ Trace collection system
- ✅ Controller interface
- ✅ Offline benchmark
- ✅ Convergence detection
- ❌ Controller doesn't learn from traces
- ❌ Traces lack intermediate steps
- ❌ Outcomes not flowing back
- ❌ Self-evolution and AutoTTS don't share knowledge

**We're at ~60% capability:** All the plumbing exists, but the brain (statistical learning) is missing.

---

## Implementation Priority

### Phase 1: Statistical Controller (CRITICAL)
**File:** `research-benchmark.el`
**What:** Learn P(kept | features) from traces with outcomes
**Output:** Controller config with learned thresholds

### Phase 2: Instrument Subagent (HIGH)
**File:** `strategic.el` or `benchmark-subagent.el`
**What:** Log actual tool calls instead of regex-extracting
**Output:** Rich step-level traces

### Phase 3: Outcome Tracking (HIGH)
**File:** `experiment-core.el` + `research-benchmark.el`
**What:** Ensure outcomes reach traces reliably
**Output:** Traces with populated `:outcomes`

### Phase 4: Knowledge Merge (MEDIUM)
**File:** `research-benchmark.el`
**What:** Cross-reference topic perf + source perf
**Output:** Topic-aware controller config

### Phase 5: Cost Tracking (LOW)
**File:** New module
**What:** Track actual API costs
**Output:** Cost-efficiency metrics

---

## Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Controller learned from data | No | Yes |
| Traces with outcomes | 0% | 80% |
| Intermediate steps per trace | 0-2 | 5-10 |
| Topic-aware controller | No | Yes |
| Cost tracking | Estimated | Actual |
| Self-evolution ↔ AutoTTS merge | No | Yes |

---

*Analysis date: 2026-05-13*
*Status: Infrastructure complete, learning layer missing*
