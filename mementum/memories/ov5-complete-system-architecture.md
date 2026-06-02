---
title: OV5 Complete System Architecture — All Relationships
φ: 0.90
e: ov5-complete-system-architecture
λ: when.designing.agent.architecture
Δ: 0.25
evidence: 5
sources:
  - gptel-auto-workflow-evolution.el (evolution cycle)
  - gptel-auto-workflow-research-benchmark.el (AutoTTS)
  - gptel-auto-experiment-ai-behaviors.el (AI Behaviors)
  - skill-routing-onto.el (Ontology Router)
  - mementum/ (git-persisted memory)
---

💡 OV5 is not a collection of independent modules. It is a **closed-loop system** where every component feeds every other component through shared execution traces.

## The Complete Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MEMENTUM                                        │
│  Git-persisted memory across sessions                                       │
│  ├── memories/      — Atomic insights (💡)                                  │
│  ├── knowledge/     — Synthesized pages (patterns, protocols, architecture) │
│  ├── state.md       — Session working memory                                │
│  └── skill-graph.json (FUTURE) — Evolved skill topology                     │
│                                                                              │
│  Purpose: ψ (AI) is ephemeral; 🐍 (system) remembers via git               │
└──────────────┬──────────────────────────────────────────────────────────────┘
               │
               │ orient() — AI reads state.md first every session
               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PIPELINE EXECUTION                                │
│  Cron-triggered every 4 hours (Pi5) or manual (local)                       │
│                                                                              │
│  1. RESEARCHER    — Searches web/repos, produces findings                   │
│  2. ANALYZER      — Selects targets from frontier                           │
│  3. EXPERIMENTS   — Executor agents modify code                             │
│  4. VALIDATION    — Tests, grader, Eight Keys scoring                       │
│  5. COMPARATOR    — Keep/discard decision                                   │
│  6. STAGING       — Human review for kept experiments                       │
└──────────────┬──────────────────────────────────────────────────────────────┘
               │
               │ Every execution produces a TRACE
               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AUTOTTS                                         │
│  Trace Analysis & Controller Evolution                                       │
│                                                                              │
│  Input: Execution traces (strategy, target, backend, outcome, token-usage)  │
│  Process:                                                                    │
│    • Load traces → check convergence → evolve controller                    │
│    • Calculate objective function (quality × efficiency)                    │
│    • Synthesize: topic performance, source effectiveness, EMA correlation   │
│  Output: strategy-guidance.json (evolved controller config)                 │
│                                                                              │
│  Triggered by: gptel-auto-workflow--run-autotts-evolution (hourly cron)    │
└──────────────┬──────────────────────────────────────────────────────────────┘
               │
               │ Controller config feeds multiple systems
               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         EVOLUTION CYCLE                                      │
│  Hourly cron: gptel-auto-workflow-evolution-run-cycle                        │
│                                                                              │
│  Step A:  AutoTTS evolution          → strategy-guidance.json               │
│  Step A.5: Controller design agent   → LLM-written controller code          │
│  Step B:   Skill evolution           → SKILL.md updates                     │
│  Step C:   Skill governance          → Health scan, canaries, dashboard     │
│  Step C.5: Backend comparison        → Reorder fallback chains              │
│  Step C.6: Model comparison          → Per-backend model preferences        │
│  Step C.7: Semantic relationships    → Knowledge graph edges                │
│  Step C.7b: Persona auto-tuning      → Eight Keys weight adjustments        │
│  Step C.7c: Ontology evolution       → Category-strategy fit learning       │
│  Step C.7d: AI Behaviors model evolve→ Backend/model selection              │
│  Step C.7e: AI Behaviors hashtag ev  → Category→hashtag mappings            │
│  Step C.7f: Validation rule evolve   → HARD CONSTRAINT suggestions          │
│  Step C.8: Allium trends             → Issue tracking + regression detect   │
│  Step C.9: VSM health check          → Wu Xing diagnostics                  │
│                                                                              │
│  Output: Multiple commits (💡 🔄 ⚒) + Updated mementum knowledge pages      │
└──────────────┬──────────────────────────────────────────────────────────────┘
               │
               │ Evolution outputs feed into next pipeline run
               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ONTOLOGY                                           │
│  Experiment Classification & Routing                                         │
│                                                                              │
│  Input: All experiment results (kept/discarded/failed)                      │
│  Process:                                                                    │
│    • Classify strategies: effective (≥50%) / promising (≥30%) / underperforming
│    • Classify targets: high-value / moderate / low-value                    │
│    • Apply recency weights: <24h 3×, 1-7d 1×, older 0.5×                   │
│  Consumers:                                                                  │
│    • Ontology Router     — strategy status bonuses (+0.10 effective)        │
│    • Ontology Strategy   — backend recommendations per strategy-target      │
│    • Research Priority   — identifies knowledge gaps                        │
│    • Evolution Cycle     — category-strategy fit learning                   │
└──────────────┬──────────────────────────────────────────────────────────────┘
               │
               │ Classification feeds routing decisions
               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ONTOLOGY ROUTER                                       │
│  8-Dimensional Skill/Backend Selection                                       │
│                                                                              │
│  Base dimensions (sum to 1.0):                                              │
│    • :task-overlap      (0.10) — keyword overlap                           │
│    • :category-fit      (0.20) — category suitability                      │
│    • :keyword-depth     (0.20) — breadth of keyword coverage               │
│    • :exclusive-match   (0.50) — identity word bonus (strongest)           │
│  Adaptive dimensions (+0.6):                                                │
│    • :keep-rate         (0.30) — historical success                        │
│    • :trend             (0.15) — recent vs overall performance             │
│    • :confidence        (0.05) — statistical confidence                    │
│    • :holographic       (0.10) — cross-category pattern memory             │
│  Gates:                                                                      │
│    • Epsilon-greedy: 15% chance to explore non-best                        │
│    • Health ladder: 3+ consecutive failures → quarantine (-50%)            │
│    • Stale penalty: unmodified 90d → -20%                                  │
│                                                                              │
│  (FUTURE: Add :graph-neighbor-success + :graph-edge-strength)              │
└──────────────┬──────────────────────────────────────────────────────────────┘
               │
               │ Selected backend + strategy + target
               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        AI BEHAVIORS                                          │
│  Hashtag-based Persona System                                                │
│                                                                              │
│  Input: Category from ontology router                                       │
│  Process:                                                                    │
│    • Expand hashtags: #deterministic → full prompt snippet                  │
│    • Composites: recursive expansion (compose files → leaf prompt.md)       │
│    • Mode tags: #=mode sets operating mode                                  │
│  Evolution:                                                                  │
│    • Records: (category × hashtag) → (kept . total)                         │
│    • Three-way: (category × strategy × hashtag)                             │
│    • Backend-aware: (category × backend × hashtag)                          │
│    • Evolves: category-defaults, combo-defaults, model selection            │
│  Output: Persona prompt injected into agent context                         │
└──────────────┬──────────────────────────────────────────────────────────────┘
               │
               │ Persona + selected skills
               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       SKILL GRAPH (FUTURE)                                   │
│  Three-Layer Capability Taxonomy                                             │
│                                                                              │
│  Atoms     — Single-purpose primitives, NEVER call skills (~99%)           │
│  Molecules — Hardcoded atom sequences, explicit workflow (~90%)            │
│  Compounds — Human-driven orchestrators, select molecules (~70%)           │
│                                                                              │
│  Design-time: Graph algorithms (PPR, BFS) suggest compositions             │
│  Runtime:     Hardcoded molecules — no traversal, no depth fragility       │
│  Evolution:   AutoTTS traces → node stats + edge reinforcement             │
│                                                                              │
│  Integration:                                                                │
│    • Router seeds from ontology scores                                     │
│    • Graph dimensions added to router (:graph-neighbor-success)            │
│    • Context budget enforces molecule size ≤10 atoms                       │
│    • AutoGo A/B tests proposed molecules                                   │
└──────────────┬──────────────────────────────────────────────────────────────┘
               │
               │ Composed prompt (task + behaviors + skills)
               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      CONTEXT MANAGEMENT                                      │
│  Token Budget Enforcement                                                    │
│                                                                              │
│  Budget: gptel-max-context-length (typically 16k tokens)                    │
│  Allocation:                                                                 │
│    • Task description:     ~2k tokens                                       │
│    • Behaviors (persona):  ~0.5k tokens                                     │
│    • Skills (molecule):    ~3k tokens (max 2400 per skill)                  │
│    • Response reserve:     ~2k tokens                                       │
│    • Conversation buffer:  ~8.5k tokens                                     │
│                                                                              │
│  Constraint: If overflow, skills truncate first (behaviors more critical)   │
│  Optimal prompt size: 2-12k chars (structure scoring)                       │
└──────────────┬──────────────────────────────────────────────────────────────┘
               │
               │ Prompt ready for agent
               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         AGENT EXECUTION                                      │
│  gptel-send with composed prompt                                            │
│                                                                              │
│  Backend: Selected by ontology router (DeepSeek/MiniMax/moonshot/DashScope)│
│  Model:   Per-backend preference (qwen3.6-plus, kimi-k2.6, etc.)           │
│  Prompt:  Task + Behaviors + Skills + Research findings                    │
│  Output:  Modified code + <think> reasoning                                │
└──────────────┬──────────────────────────────────────────────────────────────┘
               │
               │ Experiment outcome (kept/discarded/failed)
               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GRADING & BENCHMARK                                  │
│  Eight Keys Scoring + Test Validation                                        │
│                                                                              │
│  Eight Keys (φ/ε/τ/π/μ/∃/∀):                                               │
│    • φ (Vitality):     Non-repetitive, builds on discoveries               │
│    • ε (Efficiency):   Tokens per kept experiment                          │
│    • τ (Truth):        Favors reality over politeness                      │
│    • π (Progressive):  Communication quality                               │
│    • μ (Memory):       Uses past learnings                                 │
│    • ∃ (Existence):    Concrete evidence, not hand-waving                  │
│    • ∀ (Universality): Pattern generality                                   │
│  Test Validation:                                                            │
│    • Tests must pass                                                        │
│    • Nucleus validation (Eight Keys grader)                                 │
│    • Verification evidence (not hidden in <think>)                          │
│  Grader Bypass: ≥80% score + tests pass → kept regardless of comparator     │
└──────────────┬──────────────────────────────────────────────────────────────┘
               │
               │ Results recorded
               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         RESULTS STORAGE                                      │
│  TSV + Experiment Directories                                                │
│                                                                              │
│  results.tsv:                                                                │
│    • target, strategy, backend, model, decision, duration                   │
│    • eight_key_scores (JSON per-key scores)                                 │
│    • prompt_chars, output_chars                                             │
│    • kibcm-axis, hypothesis, agent-output                                   │
│                                                                              │
│  experiment directories:                                                     │
│    • Worktree with code changes                                             │
│    • Logs, traces, benchmark outputs                                        │
└──────────────────────┬──────────────────────────────────────────────────────┘
                       │
                       │ Results feed back to beginning
                       ▼
              ┌─────────────────────┐
              │   AUTOGO (Champion) │
              │   A/B Testing       │
              │                     │
              │  Compares variants: │
              │  • Strategy A vs B  │
              │  • Skill variant A  │
              │  • Backend A vs B   │
              │                     │
              │  Crowns winner      │
              │  after ≥10 samples  │
              └─────────────────────┘
```

## Data Flow Matrix

| Producer | Consumer | Data | Frequency |
|----------|----------|------|-----------|
| **Pipeline** | AutoTTS | Execution traces | Every run |
| **AutoTTS** | Evolution | strategy-guidance.json | Hourly |
| **AutoTTS** | Ontology | Topic/source performance | Hourly |
| **Evolution** | Mementum | Knowledge pages (💡) | Hourly |
| **Evolution** | AI Behaviors | Category→hashtag mappings | Hourly |
| **Evolution** | Ontology | Category-strategy fit | Hourly |
| **Evolution** | Router | Backend fallback order | Hourly |
| **Ontology** | Router | Strategy status bonuses | Every query |
| **Ontology** | Research | Knowledge gaps | Every cycle |
| **Router** | Agent | Backend + model selection | Every request |
| **Router** | Behaviors | Category classification | Every request |
| **Behaviors** | Agent | Persona prompt | Every request |
| **Skills** | Agent | Capability instructions | Every request |
| **Agent** | Grader | Modified code + reasoning | Every experiment |
| **Grader** | Results | Decision (kept/discarded) | Every experiment |
| **Results** | AutoTTS | Outcome for trace analysis | Every experiment |
| **Results** | Ontology | Strategy/target statistics | Every cycle |
| **AutoGo** | Evolution | Champion variant results | Asynchronous |
| **Mementum** | Agent | Working memory (state.md) | Every session |

## Key Closed Loops

### Loop 1: Execution → Trace → Evolution → Pipeline
```
Pipeline runs → Produces traces → AutoTTS analyzes →
Evolution updates config → Next pipeline uses updated config
```

### Loop 2: Experiment → Results → Ontology → Router → Experiment
```
Experiment completes → Results update ontology →
Router uses new ontology scores → Next experiment routed better
```

### Loop 3: Behavior → Outcome → Behavior Evolution → Behavior
```
#deterministic used → Outcome recorded →
Category→hashtag mapping evolved → Next task gets better hashtag
```

### Loop 4: Skill → Trace → Graph Evolution → Skill
```
(FUTURE) Skill executed → Trace records success →
Edge reinforced → Molecule composition improved → Next task uses better molecule
```

## The Central Insight

**AutoTTS traces are the universal currency.** Every system consumes traces:
- **AutoTTS** → evolves controller
- **Ontology** → classifies strategies
- **AI Behaviors** → learns hashtag effectiveness
- **Evolution** → updates all subsystems
- **(FUTURE) Skill Graph** → reinforces edges

A single trace format with: `category, hashtags, skill-names, backend, token-usage, outcome` feeds all four systems atomically.
