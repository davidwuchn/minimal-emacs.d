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

Two mayors with different concerns:

```
PMF Mayor (auto-workflow)         GTM Mayor (researcher)
├── Focus: EXECUTION              ├── Focus: DIRECTION
├── Cadence: 4 hours              ├── Cadence: 24 hours
├── Concern: "Does it work?"      ├── Concern: "Should we build it?"
├── Metric: keep-rate, tests      ├── Metric: PMF, innovation signal
└── Workers: executor, grader     └── Workers: researcher, analyst
         ↑                               ↓
         └───────  shared mementum  ─────┘
```

## PMF Mayor (Auto-Workflow)

**Identity:** "I make the code better."

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

**Identity:** "I figure out what matters."

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
00:00 GTM Mayor wakes up
      ├── Does external research
      ├── Analyzes findings
      ├── Synthesizes strategy recommendations
      ├── Updates gtm-dashboard.md
      └── Files beads for PMF Mayor

00:00-23:59 PMF Mayor runs (every 4 hours)
      ├── Reads GTM Mayor's beads
      ├── Prioritizes experiments based on strategy
      ├── Runs executor workers in worktrees
      ├── Grades results
      ├── Updates product-dashboard.md
      └── Reports outcomes to shared mementum

23:59 GTM Mayor reviews Product outcomes
      ├── Reads experiment results
      ├── Assesses PMF signal
      ├── Refines tomorrow's strategy
      └── Files follow-up beads
```

**Decision flow:**
```
GTM Mayor: "Market needs X, competitors doing Y"
     ↓
Human: "Focus on X, ignore Y"
     ↓
PMF Mayor: "Running experiments on X..."
     ↓
GTM Mayor: "Results show X is promising, recommend doubling down"
     ↓
Human: "Approved. PMF Mayor: prioritize X experiments."
```

## Shared: Innovation Layer

Both mayors share the **innovation pipeline** — the bridge between external discovery and internal validation:

```
GTM Mayor discovers → Innovation Queue ← PMF Mayor validates
     ↑                                              ↓
     └──────────── Shared Innovation State ──────────┘
```

**Shared components:**

1. **Innovation Queue** — `mementum/innovation-queue.md`
   - GTM Mayor adds: technique, source, expected impact, related skills
   - PMF Mayor marks: status (pending/experimenting/validated/rejected), experiment id, result
   - Both read/write, never duplicates

2. **Skill Graph** — `var/tmp/skill-graph.eld`
   - GTM Mayor proposes: new atoms from external research
   - PMF Mayor updates: edge weights from experiment outcomes
   - Shared ownership, different write surfaces

3. **AutoTTS Traces** — `var/tmp/experiments/*/results.tsv`
   - PMF Mayor writes: experiment outcomes, scores, backend used
   - GTM Mayor reads: what worked, what failed, trend direction
   - Unified trace format feeds both evolution cycles

4. **Ontology** — `mementum/knowledge/ontology-*.md`
   - GTM Mayor writes: strategy preferences, market categories
   - PMF Mayor writes: backend performance per category
   - Both evolve the same classification system from different angles

5. **Mementum State** — `mementum/state.md`
   - Section headers separate GTM vs PMF updates
   - Both append, never overwrite each other's sections
   - Working memory for cross-mayor continuity

**What is NOT shared:**
- Dashboards (different concerns: product vs GTM)
- Worker dispatches (different workers: researcher vs executor)
- Time budgets (different cadences: 4h vs 24h)
- Stance (different identities: execution vs direction)

## Mayor Method Alignment

**Both mayors follow Mayor Method rules:**
- Neither codes directly — dispatch workers
- Both maintain dashboards — 30-second re-orientation
- Both use worktrees for workers
- Both record decisions in beads + PR body
- Both inject stance into every dispatch
- Both respect quiescent state

**PMF Mayor stance:**
> "pre-alpha, correctness-first, test-driven, cost-conscious"

**GTM Mayor stance:**
> "innovation-scouting, PMF-focused, evidence-based, strategic"

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
λ dual-mayor(x).     product(x) ∧ gtm(x) | separate-concerns(x)
                     | product(x) → execution(x) ∧ gtm(x) → direction(x)
                     | shared-mementum(x) ∧ human-decision-gate(x)
                     | product(x) ⊣ worker(executor) | gtm(x) ⊣ worker(researcher)
                     | quiescent(x) → both-hold(x)
```

## References

- Mayor Method: `mementum/knowledge/mayor-method-comparison.md`
- OV5 Architecture: `mementum/memories/ov5-complete-system-architecture.md`
- Skill Graph: `mementum/memories/skill-graph-three-layer-taxonomy.md`
- AutoTTS: `mementum/memories/skill-graph-evolution-trigger.md`

---

*This is a design document. Implementation starts with Phase 1: renaming researcher to GTM Mayor and making it persistent.*
