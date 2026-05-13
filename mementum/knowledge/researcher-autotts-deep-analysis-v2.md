# Deep Analysis: Researcher + AutoTTS + Self-Evolution Integration

## Current Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  RESEARCHER (subagent)                                               │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐             │
│  │ RESEARCHER  │───→│  AutoTTS    │───→│ Controller  │             │
│  │   Skill     │    │ Controller  │    │ Decides     │             │
│  │  (prompt)   │    │  (Elisp)    │    │ STOP/CONT   │             │
│  └─────────────┘    └─────────────┘    └─────────────┘             │
│         │                    │                    │                 │
│         ↓                    ↓                    ↓                 │
│  ┌──────────────────────────────────────────────────────┐          │
│  │ Research Traces (var/tmp/research-traces/)            │          │
│  │ - JSON per session: prompt, output, strategy, conf   │          │
│  │ - Step-level data: search/fetch/analyze decisions    │          │
│  └──────────────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│  SELF-EVOLUTION                                                      │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐             │
│  │  Parse TSV  │───→│ Synthesize  │───→│ Update      │             │
│  │  Results    │    │ Insights    │    │ SKILL.md    │             │
│  └─────────────┘    └─────────────┘    └─────────────┘             │
│         │                    │                    │                 │
│         ↓                    ↓                    ↓                 │
│  ┌──────────────────────────────────────────────────────┐          │
│  │ mementum/knowledge/ + assistant/skills/auto-workflow/ │          │
│  │ - Topic performance, source effectiveness            │          │
│  │ - DIRECTIVE.md, RESEARCHER.md, token-efficiency.md   │          │
│  └──────────────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────────┘
```

## Critical Gaps Found

### Gap 1: Researcher Skill is Static, Not AutoTTS-Aware

**Current RESEARCHER.md** (91 lines):
- Has static topic list (AI agents, Emacs Lisp, LLM self-evolution)
- Has static project watch list (hermes-agent, zeroclaw, ml-intern)
- Has static source list (YouTube, X, GitHub, arXiv)
- **Effectiveness: 0.0%** (0/0 experiments)

**Problem**: Researcher doesn't know:
1. Which topics actually produced kept experiments
2. Which sources (own-repo vs external) work best for each topic
3. What the controller decided (so can't adapt its strategy)
4. How many tokens it should use (no budget awareness)

**AutoTTS Gap**: The controller decides STOP/CONTINUE but researcher skill doesn't receive this signal. The skill assumes 3-5 items per topic, max 1200 chars — but controller might have decided to STOP after turn 1.

### Gap 2: No Bidirectional Flow Between AutoTTS and Self-Evolution

**Current Flow** (one-way):
```
Research → Traces → Controller Evolves → Controller.json
                     ↓
Experiments → TSV → Self-Evolution → SKILL.md
```

**Missing**: 
- Self-evolution topic performance doesn't feed into controller priorities
- Controller source preferences don't feed into researcher topic selection
- Research traces don't include experiment outcomes (kept/discarded)

**Evidence**:
- `autotts-integration-gaps.md` gap #5: "Self-evolution tracks topic→success. AutoTTS tracks source→success. These don't talk to each other."
- `RESEARCHER.md` line 17: "research-effectiveness: 0.0%" — it doesn't even know its own performance

### Gap 3: Controller Decisions Not Fed Back to Researcher

**Current controller flow** (`strategic.el:748-857`):
1. Turn 0 runs → controller evaluates → decides STOP/CONTINUE/BRANCH/CUT
2. If CONTINUE, turn 1 runs → controller evaluates again
3. Final findings returned to analyzer

**Gap**: Researcher skill is the SAME prompt for every turn. It doesn't know:
- "Controller said CONTINUE — dig deeper"
- "Controller said BRANCH — try different angle"
- "Controller said STOP — wrap up findings"
- "Turn 2 timeout — return accumulated findings"

**Result**: Researcher wastes tokens on turn 2 doing the same thing as turn 1, instead of adapting.

### Gap 4: Statistical Controller Has No Ground Truth

**Current statistical controller** (`research-benchmark.el:172-261`):
- Learns from 0 traces with outcomes (mock traces only)
- Weights: length=+1.38, urls=+2.00, conf=+1.21, steps=+1.08
- Topic models: performance (5 traces), nil-safety (5 traces)
- **All synthetic data** — no real outcomes

**Problem**: Controller learns "what looks like good research" (URLs, structure) not "what leads to kept experiments."

**AutoTTS Paper**: Controller should learn from downstream task outcomes. Our traces have no `:outcome` field linked to experiments.

### Gap 5: Self-Evolution Doesn't Optimize Researcher Skill

**Current `evolve-researcher-skill`** (`evolution.el:1030-1100`):
- Updates frontmatter with keep rate
- Updates topic performance in body
- **Does NOT** update:
  - Source priorities (own-repo vs external)
  - Search strategy guidance
  - Token budget awareness
  - Controller integration

**Missing**: Researcher skill should evolve to say:
- "For nil-safety topics, search davidwuchn/* repos first (80% success)"
- "For performance topics, search arXiv first (60% success)"
- "Stop after 1 turn if no URLs found (controller says CUT)"

## Deep Integration Design

### Principle: Researcher is a Hybrid AutoTTS Agent

The researcher should be BOTH:
1. **AutoTTS-style**: Uses controller for real-time decisions (stop/continue/branch)
2. **Self-evolution-style**: Skill content evolves from experiment outcomes

### Architecture v2

```
┌────────────────────────────────────────────────────────────────────┐
│  RESEARCHER v2 (Hybrid AutoTTS + Self-Evolution)                   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ PHASE 0: Load Context                                         │  │
│  │ - Load evolved SKILL.md (topics, sources, effectiveness)     │  │
│  │ - Load controller config (priorities, thresholds, budget)    │  │
│  │ - Load self-evolution insights (which topics work)           │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                              ↓                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ PHASE 1: Strategy Selection (AutoTTS)                       │  │
│  │ - Controller picks strategy: own-repo-first / deep-external  │  │
│  │ - Based on: topic type, historical success rate, budget      │  │
│  │ - Injected into prompt as "Use [strategy] for [topic]"      │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                              ↓                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ PHASE 2: Multi-Turn Research (AutoTTS Controller)           │  │
│  │ - Turn 0: Search → Controller evaluates → decision           │  │
│  │ - If CONTINUE: Turn 1 with "dig deeper" prompt               │  │
│  │ - If BRANCH: Turn 1 with alternate strategy                  │  │
│  │ - If STOP/CUT: Return findings immediately                   │  │
│  │ - Controller decision INJECTED into prompt each turn         │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                              ↓                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ PHASE 3: Trace + Outcome Link                               │  │
│  │ - Save trace with experiment ID (for later outcome update)   │  │
│  │ - Controller learns from: trace features + experiment result │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                              ↓                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ PHASE 4: Self-Evolution Cycle                               │  │
│  │ - Parse experiment results → topic performance               │  │
│  │ - Update SKILL.md with:                                      │  │
│  │   * "For [topic], use [source] (X% success)"               │  │
│  │   * "Controller prefers [strategy] for [topic]"            │  │
│  │   * "Research budget: Y tokens (optimal)"                   │  │
│  └─────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
```

## Specific Improvements Needed

### 1. Dynamic Researcher Skill Content

**Current** (static in RESEARCHER.md):
```markdown
## Mission
Search external sources for actionable techniques related to:
- AI agent architectures and workflows
- Emacs Lisp AI integration patterns
...
```

**Should be** (dynamic, updated by self-evolution):
```markdown
## Evolved Research Guidance

### High-Value Topics (based on 117 experiments)
| Topic | Keep Rate | Best Source | Strategy |
|-------|-----------|-------------|----------|
| nil-safety | 28% | own-repo | Search davidwuchn/* first |
| performance | 15% | arXiv | Search papers + implementations |
| error-handling | 22% | GitHub | Check issues in gptel-agent |

### Source Effectiveness
- **Own repos**: 95% priority (2/2 experiments kept)
- **External**: 15% priority (0/1 experiments kept)
- **Use own-repo-first strategy for nil-safety topics**

### Controller Guidance
- Budget: 8000 tokens max
- Stop early if: confidence > 0.7 AND 2+ insights
- Branch if: stagnation detected (no new URLs in 2 turns)
```

### 2. Inject Controller Decisions into Research Prompt

**Current prompt** (same every turn):
```
## Instructions
1. Use WebSearch tool to find 3-5 recent/relevant items per topic
2. Use WebFetch tool to read promising pages (max 3 fetches)
...
```

**Should be** (adaptive per turn):
```
## Controller Decision: CONTINUE
Previous turn found 2 insights, confidence=0.5.
Controller says: DIG DEEPER. Focus on:
- Gaps not covered in previous findings
- Implementation details for Technique 1
- Alternative approaches not yet explored

## Budget Remaining: 4500 tokens
Use efficiently. Stop if you find 1 more high-impact insight.
```

### 3. Link Traces to Experiment Outcomes

**Current trace** (no outcome):
```json
{
  "strategy": "own-repos-first",
  "output-length": 3500,
  "confidence": 0.8,
  "source": "own-repo"
}
```

**Should have** (outcome linked):
```json
{
  "strategy": "own-repos-first",
  "output-length": 3500,
  "confidence": 0.8,
  "source": "own-repo",
  "experiment-ids": ["exp-20260513-001", "exp-20260513-002"],
  "outcome": "kept",
  "outcome-ratio": "1/2",
  "topic": "nil-safety"
}
```

### 4. Controller Should Use Self-Evolution Data

**Current controller** (heuristic only):
```elisp
(defun gptel-auto-workflow--controller-decide-research-flow (config output-length ...)
  ;; Uses: output-length, has-urls, has-structure
  ;; Doesn't use: topic performance, source effectiveness
)
```

**Should use**:
- Self-evolution topic performance → adjust strategy per topic
- Source effectiveness data → prioritize own-repo for high-success topics
- Token efficiency data → set budget based on topic complexity

### 5. Unified Evolution Hook

**Current** (separate):
```elisp
;; AutoTTS evolution
gptel-auto-workflow--run-autotts-evolution
;; Self-evolution
gptel-auto-workflow--evolve-researcher-skill
```

**Should be** (unified):
```elisp
(defun gptel-auto-workflow--unified-evolution ()
  "Single hook that evolves both AutoTTS controller AND researcher skill."
  (let* ((traces (gptel-auto-workflow--load-research-traces))
         (experiments (gptel-auto-workflow--parse-all-results))
         (topic-perf (gptel-auto-workflow--analyze-topic-performance experiments))
         (source-perf (gptel-auto-workflow--analyze-source-performance traces experiments)))
    
    ;; Layer 1: Evolve controller (AutoTTS)
    (gptel-auto-workflow--evolve-controller-from-traces traces experiments)
    
    ;; Layer 2: Evolve researcher skill (Self-Evolution)
    (gptel-auto-workflow--evolve-researcher-skill-v2 topic-perf source-perf)
    
    ;; Layer 3: Cross-layer feedback
    (gptel-auto-workflow--merge-controller-into-skill)
    (gptel-auto-workflow--merge-skill-into-controller)))
```

## Smooth Collaboration Points

### Point 1: Researcher Skill Loads Controller Config

**In RESEARCHER.md generation** (evolution.el):
```elisp
;; After evolving controller, inject config into researcher skill
(let ((controller (gptel-auto-workflow--load-autotts-controller)))
  (insert "## Controller Configuration\n")
  (insert (format "- Stop threshold: %.2f\n" (plist-get controller :min-confidence-stop)))
  (insert (format "- Budget: %d tokens\n" (plist-get controller :max-tokens-budget)))
  (insert (format "- Strategy: %s\n" (plist-get controller :active-strategy))))
```

### Point 2: Controller Uses Researcher Skill Data

**In controller decision** (strategic.el):
```elisp
(let* ((topic (gptel-auto-workflow--detect-research-topic output-text))
       (skill-data (gptel-auto-workflow--load-researcher-skill-data))
       (topic-priority (plist-get skill-data (intern (concat ":" topic)))))
  ;; Adjust thresholds based on topic priority from skill
  (when topic-priority
    (setq stop-threshold (* stop-threshold (plist-get topic-priority :success-multiplier)))))
```

### Point 3: Shared Trace Format

**Unified trace**:
```json
{
  "session": {
    "timestamp": "2026-05-13T06:45:00Z",
    "hash": "sha1-of-findings",
    "strategy": "own-repos-first"
  },
  "autotts": {
    "controller-decision": "stop",
    "confidence": 0.8,
    "turns": 1,
    "tokens-used": 3200
  },
  "self-evolution": {
    "topic": "nil-safety",
    "source": "own-repo",
    "experiment-ids": ["exp-001"],
    "outcome": "kept"
  },
  "steps": [
    {"tool": "WebSearch", "query": "...", "tokens": 450}
  ]
}
```

## Implementation Priority

### Phase 1: Link Outcomes to Traces (Critical)
- Add `:experiment-ids` and `:outcome` to trace save
- Update trace when experiment is graded
- This enables controller to learn from real data

### Phase 2: Dynamic Researcher Skill (High)
- Generate RESEARCHER.md with controller config injected
- Generate RESEARCHER.md with topic performance table
- Update skill evolution to include source effectiveness

### Phase 3: Controller Uses Self-Evolution Data (High)
- Read topic performance in controller decision
- Adjust strategy based on topic
- Set budget based on token-efficiency data

### Phase 4: Unified Evolution Hook (Medium)
- Merge `--run-autotts-evolution` and `--evolve-researcher-skill`
- Single function that updates both controller and skill
- Cross-layer feedback loop

### Phase 5: Adaptive Prompts (Low)
- Inject controller decision into research prompt
- Change instructions based on turn number and decision
- Budget awareness in researcher

## Expected Impact

| Metric | Current | Target | How |
|--------|---------|--------|-----|
| Research effectiveness | 0.0% | 15% | Topic-aware searching |
| Tokens per insight | ~4000 | ~2500 | Controller stops early |
| Controller accuracy | Heuristic | Statistical | Real outcomes |
| Turn 2 success | 0% (timeout) | 60% | Adaptive prompts |
| Skill freshness | Manual | Auto | Unified evolution |

---

*Analysis: Researcher is a prompt, AutoTTS is a controller, Self-Evolution is a feedback loop. They need to share data and adapt to each other.*
*Date: 2026-05-13*
