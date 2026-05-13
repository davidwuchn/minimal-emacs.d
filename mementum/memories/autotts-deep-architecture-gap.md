# AutoTTS Deep Architecture Analysis vs Our Researcher

## AutoTTS Architecture (from paper)

### Phase 1: Offline Trace Collection (ONE TIME)
- Run model on thousands of problems
- Save EVERY reasoning path (all branches, all steps)
- Chunk paths into fixed-length segments
- Result: Replay Store = cached database of reasoning behavior
- **Cost**: One-time compute cost
- **Key insight**: After this, NO MORE LLM CALLS needed for evaluation

### Phase 2: Controller Discovery (ITERATIVE)
- Agent writes Python controller code
- Controller decides: when to branch, stop, probe, cut
- Test controller against Replay Store (offline, deterministic)
- Get metrics: accuracy + token cost per trace
- Rewrite controller based on metrics
- Repeat until convergence
- **Cost**: $39.90 per discovery run, 160 minutes
- **Key insight**: Can test 100s of strategies for same cost as 1 online run

### Phase 3: Deployment
- Use discovered controller at inference time
- 70% token reduction vs 64 parallel chains
- Matches accuracy at 30% of cost

## Our Researcher — Deep Gaps

### Gap 1: No Trace Collection
**AutoTTS**: Saves complete reasoning traces (queries, searches, fetches, reasoning chains)
**Us**: Web searches happen, results come back, we keep final output only
**Impact**: Cannot replay or analyze what the researcher actually did

### Gap 2: No Controller Interface
**AutoTTS**: Controller is Python code with clear interface:
```python
def controller(trace, confidence_history):
    if confidence_rising(confidence_history):
        return STOP
    if confidence_stagnant(confidence_history, window=3):
        return BRANCH
    if branch_diverging(trace, consensus):
        return CUT
    return CONTINUE
```
**Us**: "Strategy" is text in a markdown file. No executable interface.
**Impact**: Cannot programmatically test, compare, or evolve strategies

### Gap 3: No Offline Evaluation
**AutoTTS**: Test controller against replay store = 0 LLM calls, instant feedback
**Us**: To test a strategy, must run full research pipeline ($$$ + time)
**Impact**: Cannot iterate quickly. Each test costs real money and minutes.

### Gap 4: No Chunking/Segmentation
**AutoTTS**: Reasoning paths chunked into segments for fine-grained analysis
**Us**: Treat research output as monolithic blob
**Impact**: Cannot analyze which PART of research was effective

### Gap 5: No Cost Attribution
**AutoTTS**: Measures tokens per trace, per decision type
**Us**: Don't know which searches cost tokens vs which produced insights
**Impact**: Cannot optimize for cost-effectiveness

### Gap 6: No Convergence Detection
**AutoTTS**: Stops when objective stops improving across rounds
**Us**: No stopping criteria. Run once, hope it's good.
**Impact**: May run suboptimal strategies indefinitely

## What We'd Need To Match AutoTTS

1. **Research Logger**: Save every WebSearch query, every WebFetch URL, every reasoning step with timestamps and tokens
2. **Segment Chunker**: Break research sessions into phases (search → fetch → analyze → synthesize)
3. **Controller DSL**: Define research strategies as code, not text. Something like:
   ```elisp
   (defresearch-strategy nil-safety-research
     :phases
     ((own-repos :max-searches 2 :stop-if-found t)
      (external-repos :max-searches 3 :condition (not own-repo-found))
      (web-search :max-searches 2 :condition (not external-found))
      (synthesize :min-insights 3))
     :stop-condition (or (own-repo-found) (external-found)))
   ```
4. **Offline Evaluator**: Replay logged research sessions with different strategies, measure:
   - Time to actionable insight
   - Tokens consumed per insight
   - Downstream keep rate
5. **Evolution Loop**: Generate strategy variants → test offline → pick best → deploy

## Current State Assessment

We have:
- ❌ Trace collection
- ❌ Controller as code
- ❌ Offline evaluation
- ❌ Chunking
- ❌ Cost attribution
- ❌ Convergence detection
- ✅ Replay store file (empty)
- ✅ Strategy guidance text (not executable)
- ✅ Evolution script (only parses, doesn't evolve)

**Verdict**: We're at ~5% of AutoTTS capability. The concept is in the prompt, but zero mechanics are implemented.
