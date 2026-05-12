# AutoTTS Integration with Self-Evolution: Deep Analysis

## What AutoTTS Actually Is

AutoTTS = **Inference-Time Strategy Optimization**
- Input: A reasoning model + a set of problems
- Output: A controller that decides when to branch/stop/cut during reasoning
- Method: Collect traces → Write controller code → Test offline → Iterate

## What Our Self-Evolution Actually Is

Self-Evolution = **Skill/Prompt Content Optimization**
- Input: Experiment results + feedback
- Output: Updated skill files (text prompts, patterns, recommendations)
- Method: Parse results → Synthesize insights → Update markdown files

## The Integration Gap

These are **complementary but orthogonal**:
- AutoTTS optimizes the REASONING PROCESS (how the model thinks)
- Self-Evolution optimizes the KNOWLEDGE CONTENT (what the model knows)

**Current state**: They're not connected. AutoTTS-style code is isolated in researcher-prompt/scripts/. Self-evolution runs separately.

## How They Should Work Together

### Layer 1: AutoTTS (Inference Strategy)
**Scope**: How the researcher subagent reasons
**Optimizes**: 
- When to search vs when to fetch vs when to stop
- How many parallel searches to run
- When confidence is high enough to stop early
**Output**: Executable controller (Python function)
**Update frequency**: Every N research sessions

### Layer 2: Self-Evolution (Knowledge Content)
**Scope**: What the researcher knows about the project
**Optimizes**:
- Which topics are high-value
- Which sources produce good insights
- What techniques work for this codebase
**Output**: Updated SKILL.md files
**Update frequency**: Every pipeline run

### Integration Points

```
Research Session Happens
  ↓
[AutoTTS Layer]
  - Save detailed reasoning trace (every tool call, every decision)
  - Controller decides: search own repos? fetch? stop?
  - Metrics: tokens consumed, insights found, time taken
  ↓
[Self-Evolution Layer]
  - Parse experiment results (was research useful?)
  - Update topic performance, source effectiveness
  - Generate new skill content
  ↓
[Feedback Loop]
  - Self-evolution tells AutoTTS: "own repos had 70% success rate"
  - AutoTTS updates controller: prioritize own repos
  - Next research session uses evolved controller + evolved knowledge
```

## Critical Missing Pieces

### 1. Detailed Trace Collection
**Current**: We save prompt + output only
**Needed**: Every tool call with:
```json
{
  "timestamp": "2026-05-13T06:45:00Z",
  "tool": "WebSearch",
  "query": "site:github.com/davidwuchn gptel nil-safety",
  "response_summary": "Found 3 repos...",
  "tokens": 450,
  "confidence_before": 0.3,
  "confidence_after": 0.7,
  "decision": "found_insights → proceed to fetch"
}
```

### 2. Controller as Executable Code
**Current**: JSON strategy definitions (static)
**Needed**: Python function that makes decisions:
```python
def research_controller(state):
    """AutoTTS-style controller for research decisions."""
    if state.confidence > 0.7 and state.source == 'own-repo':
        return Action.STOP  # High confidence, stop early
    if state.confidence_stagnant(window=2):
        return Action.BRANCH  # Try different source
    if state.tokens > 6000:
        return Action.CUT  # Over budget
    return Action.CONTINUE
```

### 3. Confidence Metrics
**Current**: None
**Needed**: Per-step confidence scores:
- After search: how relevant are results? (0-1)
- After fetch: how actionable is content? (0-1)
- After synthesize: how confident in output? (0-1)

### 4. Offline Replay
**Current**: Basic simulation
**Needed**: Full replay environment:
```python
# Replay a research session with different controller
for trace in replay_store:
    for step in trace.steps:
        action = controller.decide(step.state)
        # Simulate what would happen
        # (no actual LLM calls)
```

### 5. Joint Optimization Objective
**Current**: Separate metrics
**Needed**: Single objective function:
```
score = (keep_rate * 0.5) + (1 / tokens_per_insight * 0.3) + (novelty * 0.2)
```

## Smooth Integration Architecture

### Option A: Researcher as AutoTTS Agent
Treat the entire researcher subagent as the "model" in AutoTTS.
- Controller decides research strategy
- Traces are research sessions
- Evolve controller to minimize tokens while maximizing insight quality

**Pros**: Clean separation, matches AutoTTS paper
**Cons**: Researcher is already a subagent, adding another layer of control might be complex

### Option B: AutoTTS Inside Researcher
The researcher itself runs AutoTTS-style optimization.
- Researcher has internal "mini AutoTTS" for its own reasoning
- Self-evolution provides historical data as "replay store"
- Researcher evolves its own strategy each run

**Pros**: Natural fit, researcher controls its own optimization
**Cons**: More complex researcher prompt

### Option C: Unified Evolution (Recommended)
Single evolution loop that handles both layers:

```python
def unified_evolution():
    # Layer 1: AutoTTS - evolve inference strategy
    traces = load_research_traces()
    controller = evolve_controller(traces)
    
    # Layer 2: Self-Evolution - evolve knowledge content
    experiments = load_experiments()
    insights = synthesize_insights(experiments)
    
    # Integration: Controller uses evolved knowledge
    controller.topics = insights.top_topics
    controller.sources = insights.effective_sources
    
    # Deploy both
    save_controller(controller)
    update_skills(insights)
```

**Pros**: Unified, simple, both layers inform each other
**Cons**: Tight coupling

## Recommended Implementation

Use **Option C** with clear separation:

1. **Research Trace Logger** (enhanced)
   - Log every tool call with confidence scores
   - Store in `var/tmp/research-traces/`

2. **Controller Evolver** (new)
   - Takes traces + experiment results
   - Generates Python controller code
   - Tests offline against traces
   - Saves best controller

3. **Unified Evolution Hook**
   - Runs after each pipeline
   - Calls both: evolve_controller() + synthesize_insights()
   - Updates both: controller.json + SKILL.md

4. **Researcher Prompt Integration**
   - Load active controller at researcher startup
   - Controller provides "phase guidance" in real-time
   - SKILL.md provides "knowledge context"

This gives us:
- AutoTTS: Optimizes HOW researcher searches
- Self-Evolution: Optimizes WHAT researcher searches for
- Together: Researcher gets better at finding the right things efficiently
