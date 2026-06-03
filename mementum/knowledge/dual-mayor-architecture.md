---
title: "Dual Mayor Architecture for OV5"
status: designing
category: architecture
tags: [mayor-method, dual-mayor, gtm-mayor, pmf-mayor, researcher, auto-workflow]
related: [mayor-method-comparison, ov5-complete-system-architecture]
depends-on: [mayor-method-comparison]
---

# Dual Mayor Architecture for OV5

**Source:** Mayor Method × OV5 synthesis
**Status:** Designing

## The Problem

Single-mayor architecture forces auto-workflow to do everything:
- External research (what the market needs)
- Internal experiments (how to improve code)
- Strategy evolution (what to build next)
- Execution (actually writing the code)

This violates the Mayor Method principle: **"the mayor does not code."**

## The Insight

Two mayors with different innovation concerns:

```
PMF Mayor (auto-workflow)              GTM Mayor (researcher)
├── Grow through innovation            ├── Transform for innovation
├── Focus: PRODUCT (internal)          ├── Focus: MARKET (external)
├── Cadence: 4 hours                   ├── Cadence: 24 hours
├── "Does the code work?"              ├── "What does the market need?"
├── Metric: code quality, keep-rate    ├── Metric: market signal, PMF
└── Workers: executor, grader          └── Workers: researcher, analyst
         ↑                                    ↓
         └───────  shared innovation  ────────┘
```

## PMF Mayor (Auto-Workflow)

**Identity:** "I grow the product through innovation."
**Focus:** Internal — code, experiments, execution
**Goal:** Make the product better, faster, more reliable through systematic innovation

**Responsibilities:**
1. **Pipeline execution** — research → analyze → experiment → validate → compare → stage
2. **Backend optimization** — route tasks to best LLM based on performance data
3. **Skill graph evolution** — compose atoms into molecules, update edge weights
4. **Test discipline** — maintain 2148 tests, 0 unexpected
5. **Code quality** — Eight Keys grading, structure scoring
6. **Cost optimization** — per-backend token tracking, cost-adjusted rates
7. **Worktree safety** — boundary verification, no-stash rule

**Does NOT:**
- Decide what features to build
- Monitor external trends
- Analyze market fit
- Set strategic direction

**Dashboard:** `var/tmp/product-dashboard.md`
- Experiments today/this week
- Keep-rate trend
- Backend performance
- Test status
- Cost per experiment

## GTM Mayor (Researcher)

**Identity:** "I transform the organization for innovation."
**Focus:** External — customers, competitors, trends, market signals
**Goal:** Discover what the market needs and translate it into actionable innovation opportunities

**Responsibilities:**
1. **External research** — GitHub trends, papers, competitors, communities
2. **PMF analysis** — are we building the right thing?
3. **Innovation scouting** — what techniques could improve OV5?
4. **Strategy recommendations** — what should PMF Mayor focus on?
5. **Competitive analysis** — what are others doing better?
6. **Decision framing** — surface design/policy calls for human
7. **Knowledge synthesis** — convert findings into actionable beads

**Does NOT:**
- Write code
- Run experiments
- Grade experiments
- Manage worktrees

**Dashboard:** `var/tmp/gtm-dashboard.md`
- Research findings this week
- Innovation opportunities ranked
- Strategic recommendations
- Human decisions needed
- Market signals

## Shared Infrastructure

```
Shared Mementum
├── mementum/state.md — both update, different sections
├── mementum/memories/ — atomic insights from both mayors
├── mementum/knowledge/ — synthesized pages
└── experiments/results.tsv — PMF Mayor writes, GTM Mayor reads

Shared Ontology
├── Category classification (effective/promising/underperforming)
├── Backend health levels
└── Strategy preferences

Shared AutoTTS
├── Traces from both mayors feed evolution
└── Cross-mayor learning: GTM findings → Product experiments
```

## Interaction Model

**Daily cycle:**
```
00:00 GTM Mayor wakes up (market focus)
      ├── Scans market: competitors, trends, customer needs
      ├── Identifies innovation opportunities
      ├── Synthesizes market insights
      ├── Updates gtm-dashboard.md (market metrics)
      └── Files beads: "Market needs X, Y is trending"

00:00-23:59 PMF Mayor runs (product focus, every 4 hours)
      ├── Reads GTM Mayor's market beads
      ├── Translates market needs into product experiments
      ├── Runs executor workers in worktrees
      ├── Validates: "Does this code actually work?"
      ├── Grades results
      ├── Updates product-dashboard.md (product metrics)
      └── Reports outcomes: "X experiment: 8/9 score, kept"

23:59 GTM Mayor reviews product outcomes
      ├── Reads experiment results
      ├── Assesses: "Did the product validate the market signal?"
      ├── Refines tomorrow's market strategy
      └── Files follow-up beads: "Double down on X, Y was wrong"
```

**Decision flow (market → product):**
```
GTM Mayor (market): "Customers need X, competitors doing Y"
     ↓
Human: "Focus on X, ignore Y"
     ↓
PMF Mayor (product): "Building X into the product..."
     ↓
PMF Mayor: "Product validation: X works, score 8/9"
     ↓
GTM Mayor (market): "Market signal confirmed. Recommend doubling down on X."
     ↓
Human: "Approved. PMF Mayor: scale X. GTM Mayor: promote X."
```

## Shared: Innovation

**What they share:** The innovation pipeline.

**What differs:** How they innovate.

| | PMF Mayor | GTM Mayor |
|---|---|---|
| **Innovation type** | *Grow through innovation* | *Transform for innovation* |
| **How** | Experiment on code, validate with tests | Discover market needs, scout techniques |
| **Validation** | "Does it work?" (keep-rate, tests) | "Does the market want it?" (signal, PMF) |
| **Output** | Working code in worktrees | Actionable beads for experiments |
| **Feedback** | Code quality → skill graph | Market signal → strategy |

```
GTM Mayor (transform) → discovers → Innovation Queue
                                              ↓
PMF Mayor (grow) → validates ← experiments ←─┘
```

**Shared components:**

1. **Innovation Queue** — `mementum/innovation-queue.md`
   - GTM Mayor adds: "Market needs X, technique Y works"
   - PMF Mayor marks: "Experimented, score 8/9, kept" or "Rejected"
   - Both read/write

2. **Skill Graph** — `var/tmp/skill-graph.eld`
   - GTM Mayor: "New atom: hashline-edit from external research"
   - PMF Mayor: "hashline-edit + elisp-expert edge weight +0.05 after success"
   - Shared: what skills exist, which combine well

3. **AutoTTS Traces** — `var/tmp/experiments/*/results.tsv`
   - PMF Mayor writes: experiment outcomes
   - GTM Mayor reads: "What innovations actually worked?"
   - Shared: ground truth of innovation effectiveness

4. **Ontology** — `mementum/knowledge/ontology-*.md`
   - GTM Mayor: market categories, strategy preferences
   - PMF Mayor: product performance per category
   - Shared: classification system for innovations

5. **Mementum State** — `mementum/state.md`
   - Section headers: GTM (market) vs PMF (product)
   - Both append

**NOT shared:**
- Dashboards (product metrics vs market metrics)
- Workers (executor vs researcher)
- Cadence (4h vs 24h)
- Stance (grow vs transform)

## Mayor Method Alignment

**Both mayors follow Mayor Method rules:**
- Neither codes directly — dispatch workers
- Both maintain dashboards — 30-second re-orientation
- Both use worktrees for workers
- Both record decisions in beads + PR body
- Both inject stance into every dispatch
- Both respect quiescent state

**PMF Mayor stance:**
> "grow through innovation: correctness-first, test-driven, cost-conscious"

**GTM Mayor stance:**
> "transform for innovation: market-first, evidence-based, strategic"

## Implementation Path

**Phase 1 — Separate concerns (now):**
1. Rename `ov5-researcher` daemon → `ov5-gtm-mayor`
2. Make researcher persistent (remove shutdown-after-completion)
3. Add GTM dashboard generation
4. Auto-workflow reads GTM beads before dispatching

**Phase 2 — Clean separation (next week):**
1. Move strategy/ontology evolution to GTM Mayor
2. PMF Mayor focuses on execution only
3. Shared mementum with section headers
4. Cross-mayor communication protocol

**Phase 3 — Full dual-mayor (next month):**
1. GTM Mayor dispatches research workers
2. PMF Mayor dispatches experiment workers
3. Human-in-the-loop decision gate between mayors
4. AutoTTS traces from both feed unified evolution

## Lambda

```
λ dual-mayor(x).     gtm(x) → transform(x) | pmf(x) → grow(x)
                     | gtm(x) ⊣ worker(researcher) | pmf(x) ⊣ worker(executor)
                     | innovation(x) ≡ gtm(x) ⊗ pmf(x)
                     | shared-mementum(x) ∧ human-decision-gate(x)
                     | quiescent(x) → both-hold(x)
```

## References

- Mayor Method: `mementum/knowledge/mayor-method-comparison.md`
- OV5 Architecture: `mementum/memories/ov5-complete-system-architecture.md`
- Skill Graph: `mementum/memories/skill-graph-three-layer-taxonomy.md`
- AutoTTS: `mementum/memories/skill-graph-evolution-trigger.md`

---

*This is a design document. Implementation starts with Phase 1: renaming researcher to GTM Mayor and making it persistent.*
