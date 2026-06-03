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

Two pattern languages, one system:

```
PMF Mayor (Value Stream Pattern Language)    GTM Mayor (Product Organization Pattern Language)
├── Grow through innovation                  ├── Transform for innovation
├── Focus: VALUE FLOW (internal)             ├── Focus: ORGANIZATION (external)
├── Cadence: 4 hours                         ├── Cadence: 24 hours
├── "Does value flow?"                       ├── "What does the market need?"
├── Metric: value delivery speed/quality     ├── Metric: market signal, PMF
└── Workers: executor, grader                └── Workers: researcher, analyst
         ↑                                          ↓
         └───────  shared innovation pipeline  ─────┘
```

**PMF = Value Stream Pattern Language:** How value flows from customer need → experiment → validated code → deployed feature. Patterns: Sense → Experiment → Validate → Deploy.

**GTM = Product Organization Pattern Language:** How the organization structures to discover and deliver value. Patterns: Cross-functional teams, empowered product teams, JTBD alignment.

## PMF Mayor (Auto-Workflow)

**Identity:** "I am the Value Stream Pattern Language."
**Focus:** Internal — how value flows from need to deployed solution
**Goal:** Optimize the value stream: sense → experiment → validate → deploy

**Pattern Language — Value Stream Patterns:**

| Pattern | Description | Measure |
|---------|-------------|---------|
| Sense | Detect customer struggle or market signal | Signal clarity |
| Experiment | Build minimal solution to test hypothesis | Experiment velocity |
| Validate | Verify solution reduces struggle | Keep-rate, test pass |
| Deploy | Deliver validated value | Deployment frequency |
| Refine | Sharpen resolution of core value | Feature usage |

**Product-Led Growth 5-Step Framework:**

### Step 1 — Identify Customer's JTBD (Vision Rationale)
- Understand what "job" customers hire the product to do
- Vision: where the product must go to serve that job
- Rationale: why this job matters more than alternatives
- *Output:* `mementum/pmf/customer-jtbd.md`

### Step 2 — Define Your Market (Rhythm Imaginary)
- Map the competitive landscape around the JTBD
- Rhythm: market cadence, release cycles, customer expectations
- Imaginary: envision the product in its ideal market position
- *Output:* `mementum/pmf/market-position.md`

### Step 3 — Size Market & Create High-Growth Products (Anticipation Calculation)
- Calculate addressable market for the JTBD
- Anticipate: what features will drive 10x growth
- Build experiments that test high-growth hypotheses
- *Output:* `mementum/pmf/growth-experiments.md`

### Step 4 — Identify Needs Gaps & Competitor Weakness (Partnering Meaningful)
- Partner with GTM Mayor to validate: what do customers actually struggle with
- Identify where competitors fail to serve the JTBD
- Meaningful differentiation, not feature parity
- *Output:* `mementum/pmf/competitive-gaps.md`

### Step 5 — Identify Unmet Needs & Deploy Strategy (Simplification Resilient)
- Formulate winning product strategy based on validated unmet needs
- Simplify: remove features that don't serve the core JTBD
- Resilient: build systems that withstand market shifts
- Deploy with measurable milestones
- *Output:* `mementum/pmf/product-strategy.md`

**Does NOT:**
- Decide what features to build (follows GTM Mayor's market insights)
- Monitor external trends (receives from GTM Mayor)
- Analyze market fit (validates GTM Mayor's PMF analysis)
- Set strategic direction (executes strategy, doesn't set it)

**Dashboard:** `var/tmp/product-dashboard.md`
- Current PLG step (1-5)
- Experiments this week
- Keep-rate trend
- Growth metrics
- Competitive gap closures
- Cost per experiment

## GTM Mayor (Researcher)

**Identity:** "I am the Product Organization Pattern Language."
**Focus:** External — how the organization structures to discover and deliver value
**Goal:** Align organization structure with market needs through JTBD/ODI

**Pattern Language — Organization Patterns:**

| Pattern | Description | Measure |
|---------|-------------|---------|
| Cross-Functional Team | Team has all skills to discover + deliver | Team autonomy |
| Empowered Product Team | Team owns outcomes, not outputs | Decision speed |
| JTBD Alignment | Organization aligned around customer jobs | Strategic clarity |
| Outcome Ownership | Teams own customer outcomes | Accountability |
| Market Sensing | Org continuously scans market | Insight velocity |

**JTBD/ODI 5-Step Framework:**

**JTBD/ODI 5-Step Framework:**

### Step 1 — Define the Market (Ideology Mind)
- Define market around the **job-to-be-done**
- Infuse innovation mindset that empowers team to lead at innovation
- Gain agreement on the problem
- *Output:* `mementum/gtm/market-definition.md`

### Step 2 — Uncover Desired Outcomes (Metaphoric Soul)
- Establish common language for innovation
- Collaborate towards a solution
- Translate customer needs into measurable outcomes
- *Output:* `mementum/gtm/desired-outcomes.md`

### Step 3 — Quantify Unmet Outcomes (Cogitation Reality)
- Use right data — insights that inform strategy
- Ensure solution solves the **core problem**
- Rank outcomes by importance × satisfaction gap
- *Output:* `mementum/gtm/opportunity-scorecard.md`

### Step 4 — Discover Hidden Segments (Figurative Power)
- Align marketing, sales, development, R&D around shared understanding
- Optimize the overall system
- Find underserved segments with unmet outcomes
- *Output:* `mementum/gtm/segment-map.md`

### Step 5 — Formulate Strategy (Conceptual Time/Space)
- Unlock organization's innovation potential
- Target 5X return on innovation
- Be positive influence on the team
- Deploy winning strategy with measurable milestones
- *Output:* `mementum/gtm/strategy-roadmap.md`

**Does NOT:**
- Write code
- Run experiments
- Grade experiments
- Manage worktrees

**Dashboard:** `var/tmp/gtm-dashboard.md`
- Current JTBD step (1-5)
- Unmet outcomes ranked
- Segment opportunities
- Strategy milestones
- Human decisions needed

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

**JTBD Cycle (GTM leads, PMF validates):**
```
GTM Step 1: Define market (JTBD)
      ├── "What job are customers hiring us to do?"
      ├── Files: market-definition.md
      └── PMF validates: "Can we build for this job?"

GTM Step 2: Uncover desired outcomes
      ├── "What outcomes matter? How to measure?"
      ├── Files: desired-outcomes.md
      └── PMF validates: "Can we measure this in code?"

GTM Step 3: Quantify unmet outcomes
      ├── "Which outcomes have biggest gap?"
      ├── Files: opportunity-scorecard.md
      └── PMF validates: "Can we close this gap?"

GTM Step 4: Discover hidden segments
      ├── "Who is most underserved?"
      ├── Files: segment-map.md
      └── PMF validates: "Can we serve this segment?"

GTM Step 5: Formulate strategy
      ├── "How do we win? What's the roadmap?"
      ├── Files: strategy-roadmap.md
      └── PMF validates: "Can we execute this strategy?"

PMF runs continuously (every 4 hours):
      ├── Reads GTM's current JTBD artifacts
      ├── Runs experiments on highest-opportunity items
      ├── Reports: "Outcome X: gap closed from 0.3 to 0.8"
      └── Updates product-dashboard.md
```

**JTBD Decision flow:**
```
GTM Step 3: "Outcome 'fast startup' is unmet (importance 9.2, satisfaction 3.1)"
     ↓
Human: "Priority: close this gap"
     ↓
PMF Mayor: "Experiment: optimize startup path..."
     ↓
PMF Mayor: "Result: startup time reduced 40%, score 8/9"
     ↓
GTM Step 5: "Strategy validated. Gap closed from 3.1→7.8. Next: segment expansion."
     ↓
Human: "Approved. PMF: scale this optimization. GTM: find next unmet outcome."
```

## Shared: Innovation

**Two pattern languages, one innovation system.**

The Value Stream Pattern Language (PMF) and Product Organization Pattern Language (GTM) intersect at the innovation pipeline:

```
GTM (Org Patterns) → discovers → Innovation Queue → PMF (Value Stream) validates
         ↑                                                   ↓
         └────────────── Shared Patterns ─────────────────────┘
```

| Dimension | PMF: Value Stream Pattern Language | GTM: Product Organization Pattern Language |
|---|---|---|
| **Core pattern** | Sense → Experiment → Validate → Deploy | Cross-functional → Empowered → JTBD-aligned |
| **Framework** | 5-step PLG | 5-step JTBD/ODI |
| **Innovation type** | *Grow through innovation* | *Transform for innovation* |
| **Validation** | "Does value flow?" (keep-rate, tests) | "Does the org align with market?" (signal, PMF) |
| **Output** | Working code in worktrees | Org design + market artifacts |
| **Feedback** | Value metrics → skill graph | Market signal → org structure |

**Cross-pattern flow:**
```
GTM Step 1 (Ideology Mind): Define market around JTBD
         ↓
PMF Step 1 (Vision Rationale): Identify customer's JTBD
         ↓
GTM Step 2 (Metaphoric Soul): Uncover desired outcomes
         ↓
PMF Step 2 (Rhythm Imaginary): Define market position
         ↓
GTM Step 3 (Cogitation Reality): Quantify unmet outcomes
         ↓
PMF Step 3 (Anticipation Calculation): Size market, build high-growth experiments
         ↓
GTM Step 4 (Figurative Power): Discover hidden segments
         ↓
PMF Step 4 (Partnering Meaningful): Find needs gaps & competitor weakness
         ↓
GTM Step 5 (Conceptual Time/Space): Formulate strategy
         ↓
PMF Step 5 (Simplification Resilient): Deploy winning product strategy
```

**Innovation Principles:**

1. **Resolution Refined** — Innovation is not about adding features; it's about sharpening the resolution of the product's core value. Every experiment should make the JTBD clearer, not blur it with options.
2. **Struggle Well** — The best innovations come from understanding the customer's struggle, not from celebrating the solution. PMF Mayor validates: "Does this reduce struggle?" GTM Mayor discovers: "Where is the struggle?"

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
