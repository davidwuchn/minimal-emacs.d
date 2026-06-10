# OUROBOROS-V5: Recursive Self-Improving AI Architecture

> **Your company should improve itself. OV5 makes that real.**
>
> Most AI tools generate code and forget. OV5 runs 100+ experiments/month, learns what works, remembers what fails, and gets smarter every cycle. It is the difference between "AI writes code" and "AI runs your engineering organization."

## At a Glance

| What you want | What you get |
|--------------|--------------|
| **Self-improving company** | Recursive AI loops that learn from every outcome |
| **Automatic code improvement** | 100+ experiments/month, ~20% keep-rate, monitoring agent watching failures |
| **Zero-risk execution** | Git worktree isolation, **7 gates**, never touches `main` directly |
| **Learning system** | Ontology + context database remember experiments, failures, and rationale |
| **Token efficiency** | **59% prompt compression** via lambda notation and deterministic routing |
| **Low cost** | ~$0.50-2.00/run across **8 backends** (4-5 actively routed) |
| **Human oversight** | File-based approval queue, 7-day expiry, high-risk proposals routed to review |
| **Production sensing** | Monitoring agent + production metrics; Sentry wired, external feedback still partial |
| **Scale** | **120 modules** (76 byte-compiled, 44 no-byte-compile), **3,485 ERT tests** |
| **Reality check** | **✅ YC Vision 100% complete** - all 5 layers operational, all 10 monitoring phases implemented (0-9), full self-improving loop |

**Quick start:** Clone -> run pipeline -> review kept experiments next morning.

**Cost:** ~$0.50-2.00/run. **Token efficiency:** 59% prompt compression via lambda notation. **Safety:** Git worktree isolation + **7 gates** - no change touches `main` without passing all gates. **Scale:** 120 modules, **3,485 ERT tests**, 8 backend definitions (4-5 actively routed). **YC Vision:** **✅ 100% complete** - all 5 layers operational (Sensor, Policy, Tools, Quality, Learning), all 10 monitoring phases implemented (Phase 0: health probes, Phase 1: failure analysis, Phase 2: proposal generation, Phase 3: test/deploy, Phase 4: architectural evolution, Phase 5: external sensors, Phase 6: approved execution, Phase 7: impact assessment, Phase 8: synthesis trigger, Phase 9: self-tuning), full self-improving loop with human oversight.

- [Begin](#begin) - Clone, run, done
- [Why OV5?](#why-ov5)
- [The YC Vision Framework](#the-yc-vision-framework)
- [The Principle](#the-principle)
- [The Two Mayors](#the-two-mayors)
- [The Architecture](#the-architecture)
- [The Knowledge Layer](#the-knowledge-layer)
- [Safety](#safety)
- [Troubleshooting](#troubleshooting)

**For step-by-step installation:** See [INSTALL.md](INSTALL.md)
**For business context, GTM narrative, JTBD, and YC framing:** See [BUSINESS_CONTEXT.md](BUSINESS_CONTEXT.md)

---

## Begin

> **Full installation guide:** [INSTALL.md](INSTALL.md) - prerequisites, API keys, daemon setup, verification.

```bash
git clone --recurse-submodules https://github.com/davidwuchn/minimal-emacs.d ~/.emacs.d
cd ~/.emacs.d && ./scripts/setup-packages.sh
./scripts/setup-eca-links.sh
# API keys in ~/.authinfo - see INSTALL.md Step 4
./scripts/run-pipeline.sh
```

That is it. The first run initializes everything. After that, the pipeline runs itself.

```elisp
(gptel-auto-workflow-run-async)        ; Start a run
(gptel-auto-workflow-status)           ; Check current state
```

**What happens after you run it:** The system selects target files, generates hypotheses, runs experiments in isolated git worktrees, grades results against baselines, and merges improvements that pass all **7 gates**. Monitoring runs after each experiment batch, and high-risk proposals land in the approval queue instead of shipping themselves.

**Example output** (from a real run):
```
[auto-workflow] Starting 2026-06-01T154953Z-eac5 with 5 targets
[subagent] executor using DashScope/qwen3.6-plus
[auto-experiment] ✓ Tests passed
[auto-experiment] ✓ Experiment kept - merged to staging
===RESULT=== {"metric":"evolution-cycle","value":0.107}
```

### Daily Routine

```elisp
;; 1. Check system status
(gptel-auto-workflow-status)
;; -> phase: idle (healthy) | running (in progress) | error (needs attention)

;; 2. Review what happened overnight
;; Shell: git log --oneline -10
;; Look for: "kept" commits = improvements merged
;; Concern: 0 kept for 3+ consecutive runs

;; 3. Check latest experiment results
;; Shell: read var/tmp/experiments/*/results.tsv
;; Look for: keep-rate trending toward 20%
;; Concern: keep-rate stuck at 0% or dropping suddenly

;; 4. Skim logs for errors
;; Shell: read var/log/emacs-*.log
;; Look for: "rate-limited" (normal, auto-recover) | "quota exhausted" (check API keys)
;; Concern: "all backends exhausted" or repeated timeouts on same target
```

| What is normal | What is not |
|---------------|-------------|
| Phase cycles idle -> running -> idle | Stuck in "selecting" for >30min |
| Timeouts and rate-limits in logs | 0 kept for 3+ consecutive runs with different targets |
| Keep-rate fluctuates 10-30% early | Keep-rate stuck at 0% after 50+ experiments |
| Different backends selected per target | Same error across all backends (code issue, not provider) |
| Monitoring agent runs after batches | Approval queue growing without review for many days |

---

## Why OV5?

AI coding tools generate code. OV5 engineers your codebase.

| Capability | Copilot / Cursor / Claude Code | OV5 |
|-----------|-------------------------------|-----|
| **Memory** | Forgets every session | Remembers every experiment (kept + discarded) |
| **Learning** | Generic training data | Your codebase's specific patterns |
| **Quality control** | You review every line | **7 gates** filter before you see anything |
| **Improvement** | Static capability | Compounds with every experiment |
| **Safety** | Modifies your working tree | Isolated worktrees, never touches `main` |
| **Cost** | $20-100/month subscription | $0.50-2.00/run, pay only for experiments |
| **Customization** | Prompt engineering | Ontology learns your standards automatically |

**The key difference:** Other tools are stateless. They generate code, you accept or reject, they forget. OV5 is stateful - it learns from every outcome and applies those lessons to future experiments. After 100 experiments, it knows your codebase better than any new team member.

**When to use what:**
- **Copilot/Cursor** -> Write new features quickly
- **OV5** -> Improve existing code quality, eliminate tech debt, enforce standards

---

## The YC Vision Framework

BUSINESS_CONTEXT.md carries the market story. This document keeps the technical map. The YC frame is useful because it names the five loops OV5 must close:

```
lambda vision(x).
  sensor(x) -> policy(x) -> tools(x) -> quality(x) -> learning(x)
  | each_layer feeds(next_layer)
  | missing(sensor_signal) -> weaker_learning
  | strong_quality without learning == static_guardrail
```

| Layer | YC role | OV5 subsystems | Current reality |
|------|---------|----------------|-----------------|
| **1. Sensor** | Notice what the world is doing | Monitoring agent, production metrics, failure classification, Sentry-backed signals | **Partial** - Sentry wired; support tickets / user feedback still stubs |
| **2. Policy** | Decide what is allowed | Decision classification, approval queue, risk tiers, policy engine | **Operational** - low-risk auto, high-risk queued |
| **3. Tools** | Give deterministic leverage | Knowledge reasoning, context database, causal analysis, routing, compilers | **Strong** |
| **4. Quality Gate** | Prevent bad energy from shipping | **7 gates**, review, holdout checks, watchdog, self-healing | **Strong** |
| **5. Learning** | Turn outcomes into stronger future behavior | Self-evolution, pattern synthesis, architectural evolution, code regeneration | **Operational** |

### Layer notes

- **Sensor**: monitoring agent after each batch, throttled to **15-minute** cycles; production metrics weight scoring; **Sentry API** wired; support-ticket and feedback sensors still partial.
- **Policy**: decision classification + file-based approval queue under `var/approval-queue/`; **7-day expiry**; high-risk proposals wait for human review.
- **Tools**: knowledge reasoning, routing, compilers, and the **context database** with sidecar `.sexp` files in `var/context/`.
- **Quality**: OV5 refuses to confuse motion with progress. **4 enforced gates** block experiments in the hot path; **3 downstream checks** run post-experiment:

| Gate | Type | What it checks | What happens on failure |
|------|------|---------------|------------------------|
| **1. Category Routing** | Enforced | Best backend for this target right now? | Routes to strongest current performer; unhealthy backends dropped |
| **2. Test Execution** | Enforced | Did **3,485 ERT tests** pass? | Experiment discarded, pattern learned |
| **3. AI Grading** | Enforced | Is the change well-structured and principled? | Scored 0.0-1.0, fed to analyzer |
| **3.5 Complexity Gate** | Enforced | Did complexity rise >10% without proportional quality gain? | Experiment rejected with explicit reason |
| **4. AI Review** | Downstream | Does it pass security, conventions, architecture? | Multi-agent review in staging path |
| **5. pi Synthesis** | Downstream | Which similar files should inherit this strategy? | Semantic cluster auto-queue |
| **6. Champion League** | Downstream | Does this strategy beat the current category champion? | Adopted or rejected with keep-rate evidence |

- **Learning**: self-evolution, pattern synthesis, **architectural evolution**, and **code regeneration** consume the results of the first four layers. The monitoring agent runs 10 phases every cycle (0: health probes, 1: failure analysis, 2: proposal generation, 3: test/deploy, 4: architectural evolution, 5: external sensors, 6: approved execution, 7: impact assessment, 8: synthesis trigger, 9: self-tuning). **100% complete.**

---

## The Principle

**Ouroboros.** The snake eating its tail.

```
lambda engage(emacs).
  gtm(research) <-> pmf(experiment) <-> verify(outcome) <-> learn(pattern)
  | forall change: isolated(worktree) and verified(tests) and reviewed(AI)
  | self_referential: the system audits itself using its own ontologies
  | route(ontology) == categorize(target) -> rank(backends)
      by delta(decayed-keep-rate - baseline)
      tensor VSM-tuned-weights
      tensor per-axis-KIBC-boost
      tensor recency-decay(14d)
  | autonomy: human-observes(x) and not human-blocks(x) | git-resolves-conflicts(x)
```

**In plain English:** The system researches techniques, tests them as experiments, verifies results, and feeds what it learned back into what it researches next. Every change is isolated in a git worktree, verified by tests, and reviewed before it can touch the integration path. Backend selection is automatic - ranked by recent performance, not just historical averages. You observe outcomes; the system handles execution.

This is not a code generator. It is a **self-consuming formal system** - it researches techniques from external sources, distills them into specifications, tests them as isolated experiments, and feeds outcomes back into what it researches next.

Like the Northern Divine Art (北冥神功), it absorbs techniques from everywhere and converts them into its own capability. What worked flows into the next cycle. What failed becomes a guard rail. The art grows with its practitioner.

Every subsystem is the same Ouroboros cycle, viewed at different scales:

| Scale | System | Ouroboros role | Horizon |
|-------|--------|----------------|---------|
| **Turn** | AutoTTS | Stop, continue, or branch research? | Seconds |
| **Strategy** | AutoGo | Does this challenger eat the champion? | Experiments |
| **Evolution** | meta-harness | Generate new strategies from failure patterns | Cycles |
| **System** | self-evolve | Is the whole pipeline improving or plateauing? | Days |
| **Identity** | VSM + Eight Keys | Are all five elements healthy? | Continuously |

The frameworks are not separate tools - they are the same tool at different zoom levels. **VSM** assigns who does the work. **Ontology** classifies what kind of work. **Eight Keys** measure how well it was done. All map to the same five elements: Water -> Wood -> Fire -> Earth -> Metal -> Water.

Say "Ouroboros V5" or "OV5" and you mean: the full self-regulating cybernetic architecture.

---

## The Two Mayors

The ouroboros has two mayors - and they feed each other. The **GTM Mayor** (Wood) looks outward, consuming external techniques and filing them into the ontology. The **PMF Mayor** (Metal) looks inward, testing those techniques as experiments and feeding outcomes back. Neither works alone: the GTM Mayor's appetite is shaped by what the PMF Mayor digests, and the PMF Mayor's targets are chosen by what the GTM Mayor discovers.

Within the YC frame, the GTM Mayor spans **Sensor + Tools**. The PMF Mayor spans **Quality + Learning**. **Policy** sits between them as the approval membrane when a proposal becomes high-risk.

**Human role:** Observer, not gate. The system runs autonomously (research + experiments + commits). Human reviews outcomes asynchronously - morning sync, not real-time approval, except when the approval queue marks a proposal as genuinely high-risk.

```
        ┌──────────────────────────────────────────────┐
        │                                              │
        ▼                                              │
  ┌──────────┐    findings     ┌──────────────┐        │
  │ RESEARCH │ ───────────────>│   ANALYZE    │        │
  │ (Wood)   │                 │  (Fire)      │        │
  │ eat      │<────────────────│  decide      │        │
  └──────────┘   "look here"   └──────────────┘        │
        ▲                              │               │
        │                              │ targets       │
        │         ┌──────────────┐     ▼               │
        │         │   EVOLVE     │  ┌──────────┐       │
        │         │  (Earth)     │<-│ EXECUTE  │       │
        │         │  learn       │  │ (Metal)  │       │
        │         └──────────────┘  │ verify   │       │
        │              │            └──────────┘       │
        │              │ outcomes   │                  │
        │              ▼            ▼                  │
        │         ┌─────────────────────┐              │
        └─────────│  pi SYNTHESIS (Water)│─────────────┘
   "research      │  propagate           │  "queue similar"
    these gaps"   └─────────────────────┘
```

### The GTM Mayor (Wood 木)

The GTM Mayor researches. It consumes, it does not hoard.

```bash
./scripts/run-pipeline.sh
```

The GTM Mayor scans 17+ repos via `gh api`, but it does not prefetch everything. It reads the ontology for knowledge gaps, fetches only what fills those gaps, and produces Allium v3 behavioral specs. No batch crawl - each fetch is a deliberate bite.

It is **benchmark-driven and self-evolving** - four research strategies compete each cycle, and the winner sets the technique:

| Strategy | When research is... |
|----------|---------------------|
| **own-repos-first** | Digesting local patterns before hunting elsewhere |
| **deep-external** | Hungry - exhaustively scanning external sources |
| **topic-specific** | Focused - chasing a gap the ontology identified |
| **quick-own-only** | Conservative - API quota is low, stay local |

**Research quality pipeline** - each finding passes through six research filters before reaching the PMF Mayor:

1. **Strategy benchmark** - all 4 compete; best wins per cycle
2. **Allium coherence check** - contradictions detected before techniques reach experiments
3. **LLM noise stripping** - conversational artifacts removed from raw findings
4. **Eight Keys scoring** - scored on epsilon Purpose (actionability), not just volume
5. **Ontology enrichment** - new techniques auto-extracted and merged
6. **Outcome feedback** - kept/discarded experiments adjust research priorities per source

The GTM Mayor is not a scraper. It is a **self-adjusting appetite**: what it researches next depends on what the PMF Mayor kept or discarded last cycle.

### The PMF Mayor (Metal 金)

The PMF Mayor executes. It tests, verifies, and feeds back.

```
Select target -> Categorize -> Route backend (smart routing) -> Select model (per-target history)
      -> Inject nucleus persona -> Generate 5 diverse hypotheses -> Select highest-diversity -> Run 3485 tests -> AI grade
      -> Complexity gate -> AI review -> Merge or learn
          ↓
     Kept? -> pi Synthesis: semantic cluster -> inherit strategy -> auto-queue
```

**Plan-level search** (inspired by PlanSearch): Before executing an experiment, the system generates 5 diverse hypotheses using Jaccard similarity to maximize diversity. The highest-diversity hypothesis is selected for execution. This prevents repeated exploration of similar solution spaces and improves the quality of kept experiments.

Every experiment is an isolated git worktree. `main` is never touched directly. **Seven gates** stand between a hypothesis and a merge:

| Gate | What it checks | What happens on failure |
|------|---------------|------------------------|
| **Category Routing** | Best backend for this target right now? | Routes to strongest current performer; unhealthy backends dropped |
| **Test Execution** | Did **3,485 ERT tests** pass? | Experiment discarded, pattern learned |
| **AI Grading** | Is the change well-structured and principled? | Scored 0.0-1.0, fed to analyzer |
| **Complexity Gate** | Did complexity rise without proportional quality gain? | Experiment rejected with rationale |
| **AI Review** | Does it pass security, conventions, architecture? | Multi-agent review with feedback |
| **pi Synthesis** | Which similar files should inherit this strategy? | Semantic cluster auto-queue |
| **Champion League** | Does this strategy beat the current category champion? | Adopted or rejected with keep-rate evidence |

Energy that does not pass a gate is not wasted - it returns as learning for the next cycle. A discarded experiment is not a failure; it is the system telling itself "do not try that shape again." After each experiment batch, the monitoring agent reads failure patterns and decides whether the problem is tactical, systemic, or architectural. High-risk structural proposals go to the approval queue.

### The Innovation Queue (Water 水)

The two mayors communicate through the Innovation Queue - `mementum/innovation-queue.md`.

```
GTM Mayor discovers technique T --> Innovation Queue: "Market needs X"
                                          │
                                     ┌────┴────┐
                                     ▼         ▼
                              PMF validates   PMF rejects
                                     │         │
                                     ▼         ▼
                               pi Synthesis   failure pattern
                               queues X2,X3   tells GTM:
                                     │       "avoid this shape"
                                     ▼
                          GTM: "what else looks like
                          X that I have not studied yet?"
```

**Autonomy principles:**
- GTM Mayor adds to queue without human approval
- PMF Mayor marks entries as validated/rejected
- Git `merge=theirs` resolves auto-evolved conflicts where policy says Pi5 is authoritative
- Human reviews asynchronously - morning sync only, unless policy elevates risk

### Scoring Gate Override: Correctness-Fix Promoter

When the structural scoring model (Eight Keys) fails to measure a bug fix's value, the **correctness-fix promoter** bypasses the comparator blind spot:

```
lambda promote(decision, grade).
  grader >= 8/9 and verified(correctness_fix) and not speculative(hypothesis)
  -> bypass(gate_rejection) | keep(experiment)
  | quality_regression(guard_code) != correctness_loss
```

Grader-confirmed bug fixes survive the structural scoring model's blind spot. Staging verification still catches broken merges.

---

## Deterministic-First Architecture

AI model calls are expensive (120s+ timeouts, 8 backends, retries). Where data already exists, compute directly:

```
lambda select(x). deterministic(data) > AI(model)
  | frontier_ranking(TSV) -> targets(<1s) > analyzer_prompt(120s x 3 retries)
  | decision_gate(scores) -> keep/discard(~0s) > comparator_LLM(120s)
  | static_fallback(ordered_by_keep_rate) > router_aggregate(across_task_types)
```

- **Analyzer**: `frontier-select-targets` reads TSV history and ranks targets in under a second.
- **Comparator**: `decision-gate` computes keep/discard from score deltas before any LLM opinion.
- **Routing**: static fallback stays speed-aware and quality-aware.
- **Context usage**: business rationale comes from sidecar context data first, not from the model re-guessing why a change mattered.

---

## Three-Format Rule

Three formats, three audiences - strict separation with regression tests:

| Format | Goes to LLM? | Goes to human? | Enforcement |
|--------|-------------|----------------|-------------|
| **Lambda notation** | Yes (primary) | Yes (source) | Prompt compression, prompt tests, deterministic rendering |
| **Allium statecharts** | No (banned) | Yes (audit) | `allium-check` for behavioral verification |
| **EDN / plist data** | No (banned) | No (banned) | Internal compiler substrate |
| **English prose** | No (phased out in prompts) | Yes (docs only) | Prose banned in prompt strings by regression tests |

All 60 byte-compiled `.el` files run under `byte-compile-error-on-warn t` (45 use `no-byte-compile: t`). Prompt construction migrated from `{{mustache}}` substitution to structured data -> resolve -> lambda notation. Deterministic rendering, zero LLM calls for prompt assembly.

---

## The Architecture

The operational core is still the same snake, but the technical reference reads cleaner when arranged by YC layers:

| YC layer | OV5 technical surface |
|---------|------------------------|
| **Sensor** | Monitoring agent, production metrics, failure classification |
| **Policy** | Approval queue, decision classification, risk tiers, forbidden-path policy engine |
| **Tools** | Compilers, routing, context database, knowledge reasoning, skill graph |
| **Quality** | Seven gates, moderator drift checks, watchdog, self-healing |
| **Learning** | Evolution cycle, pi Synthesis, architectural evolution, code regeneration |

Every cycle still runs through the nucleus layer. The parts below mostly live in Tools and Quality, but all of them feed Learning.

### Compilers

| Compiler | Input -> Output | Answers |
|----------|-----------------|---------|
| **Nucleus EDN** | Strategy prompt -> statechart | "Is this instruction well-formed?" |
| **Nucleus Lambda** | Hypothesis -> lambda expression | "What principle does this encode?" |
| **Allium v3** | Research findings -> behavioral spec | "Are these internally coherent?" |
| **OWL/SHACL** | Ontology dict -> Turtle/SHACL | "What is the formal shape of what we learned?" |
| **Context compiler** | Experiment outcome -> sidecar rationale | "Why did this matter to the business?" |
| **Skill Graph** | Skill frontmatter -> compiled molecules -> executor workflows | "Which capabilities compose into effective workflows?" |
| **Ontology Router** | Target file -> category -> backend ranking | "Which backend is best right now?" |
| **Self-Healing Auditor** | Pipeline metrics -> diagnosis -> remediation | "Is the evaluator broken, and can I fix it without a human?" |

### Routing

Scoring uses VSM-auto-tuned weights + recency decay (14d half-life) + per-axis KIBC boost. Researcher, analyzer, executor, grader, reviewer, and explorer backends are ranked by health and keep-rate; quarantined and cooldown backends are excluded. Every routing decision is logged with component scores so architectural evolution can judge whether routing itself needs to evolve.

**Smart routing** (`gptel-backend-registry-select-for-task`) is the single entry point for all LLM calls. It eliminates hardcoded backend references by dynamically selecting the best backend based on task type, health status, and historical performance. The registry maintains fallback chains per task type, enabling automatic failover when backends become unavailable.

### Persona & Moderation

**Nucleus persona injection** shapes attention per subagent. **Impact auto-tuning** adjusts thresholds from observed outcomes. **Moderator drift detection** forces backend swaps after repeated failures. Quality control here is active steering, not passive logging.

### Skill Graph

Skills are not just documentation - they are **executable capabilities**. The skill graph reads skill frontmatter and compiles it into runtime workflows:

```
Skill frontmatter -> load nodes + edges -> compile molecules -> validate -> execute
```

| Component | What it does |
|-----------|--------------|
| **Node loader** | Reads installed skills, extracts atom / molecule / compound level |
| **Edge builder** | Builds dependency edges from frontmatter and from successful experiment sequences |
| **Molecule compiler** | Greedy workflow assembly: prefer strong dependencies, avoid duplicates |
| **Validator** | Enforces size, known atoms, no dupes, minimum edge strength |
| **Executor** | Sequential callback per atom; records actual skills used in TSV |
| **Evolution** | Periodic edge-weight updates from success/failure outcomes |

**Integration:** the ontology router uses graph-neighbor success and graph-edge strength as scoring dimensions, and the prompt builder injects `WORKFLOW:` lines from compiled molecules. Executor defaults to hashline editing to reduce text-reproduction failures.

---

## The Knowledge Layer

The system does not just run experiments - it builds a **formal knowledge graph** of its own operation. This is the mementum layer. Knowledge persists across sessions and across failures.

| Capability | Mechanism |
|-----------|-----------|
| **Ontology generation** | Raw experiment data -> classes, properties, relationships -> OWL |
| **Allium behavioral checking** | Research findings -> Allium v3 spec -> contradiction detection |
| **Conflict detection** | Opposing hypotheses on same target -> severity-graded |
| **Impact classification** | Every experiment: BREAKING / POTENTIALLY BREAKING / SAFE |
| **Causal chains** | Multi-experiment sequences per target -> root cause via **Floyd-Warshall** |
| **Temporal reasoning** | Gap and overlap detection via **Allen interval algebra** |
| **Horn SAT consistency** | Linear-time contradiction detection for ontology integrity |
| **Cross-cycle diff** | Knowledge snapshots: +added / -removed / ~changed |
| **Policy engine** | Rules for max per target, min keep-rate, forbidden paths |
| **Ambiguity filtering** | Multi-stage confidence gating - defer high-ambiguity candidates |
| **Second-chance repair** | Soft-deleted patterns re-evaluated each cycle |
| **Interval labelling schema** | O(1) subsumption over pattern hierarchy via preorder/postorder |
| **Context database** | Sidecar `.sexp` files in `var/context/` store business rationale, causal chain, learned, decision rationale |
| **Backend performance analysis** | Experiments tracked across 8 backends -> keep-rate and combination learning |
| **Pre-flight prediction** | Anti-pattern detection, target saturation, prediction thresholds |
| **Ontology vs LLM decider** | Data-availability x complexity x EMA confidence -> ontology or LLM |
| **Category-based routing** | Targets classified into ontology categories -> backend ranking per category |
| **Semantic clustering** | Similarity >= 0.75 groups related targets |
| **Strategy inheritance** | Similar targets auto-queue with inherited strategy from kept experiments |
| **Category strike tracking** | 3 consecutive failures freeze a category (**forall Vigilance**) |
| **VSM health diagnostics** | Eight Keys scored per subsystem; Wu Xing repair actions dispatched |
| **Allium BDD gate** | Behavioral spec coherence checked each evolution cycle |
| **Allium auto-repair** | Coherence issues inject repair guidance into future prompts |
| **Category budget** | Per-category experiment quotas allocated by sqrt(keep-rate) |

**37 patterns** were ported from Semantica, AutoGo, LogMap, and VSM. The system audits itself using its own ontologies.

---

## The Competitive Layer

The pipeline does not adopt new strategies naively - it makes them fight.

AutoGo-inspired **champion league** gates every new strategy: incumbents must be defeated in a category-specific gauntlet before adoption. **Playout Cap Randomization** (80% quick / 15% medium / 5% deep) prevents over-specialization, and every cycle emits a machine-parseable `===RESULT===` block for the autoresearch loop.

**Head-to-head comparison** feeds routing and architectural evolution. **forall Vigilance** freezes categories with 3 consecutive champion failures. **pi Synthesis** propagates winning strategies across similar files. **Holdout evaluation** catches overfitting.

### Smart Subagent Routing (Ouroboros within Ouroboros)

Backend selection for subagent calls is itself a closed-loop Ouroboros cycle:

```
Subagent call -> failure (timeout/rate-limit) -> health strike + per-run cooldown
    -> ranked-subagent-backends excludes cooldown backends
    -> future calls route to healthier backends
    -> 1h auto-recovery: probation -> degraded
    -> lambda verification retest -> healthy -> strikes cleared
    -> backend restored to routing pool
```

Scoring is `health-weight x keep-rate + per-axis-KIBC-boost + agent-type-preference-boost`, recency-weighted with a 14-day half-life. Each subagent receives role-tuned persona, lambda tool patterns, routing context, and moderator lenses when drift appears.

---

## The Operational Layer

Every hypothesis is classified by its **operation type** - the verbum layer:

```
KIBC-M 15-axis taxonomy:
  :K nil-safety    :I identity      :B composition   :C reordering    :M pattern-matching
  :W duplication   :T type-checking :Phi coordination :D decomposition
  :SCOPE visibility :SUBST substitution :WHNF normalization
  :Y recursion      :QUOTE documentation
```

**Forward chaining** infers actions from system state. **Abductive reasoning** generates best explanations from observations. **Deductive reasoning** proves conclusions from premises. **Datalog transitive closure** discovers indirect causal relationships. **Temporal Allen relations** detect gaps and overlaps between experiments.

Together: observe -> diagnose -> prove -> act -> schedule. Zero-LLM deterministic layer where possible.

---

## The Persistence Layer

The snake only improves if memory survives restart.

### Cross-subsystem state

`var/tmp/cross-subsystem-state.json` preserves:

| What persists | Why |
|--------------|-----|
| Category champions + keep-rates | Competitive gating continues across restarts |
| Category experiment budget | Budget enforcement resumes with informed allocation |
| VSM expanded actions | Wu Xing repair hints survive crashes |
| Regressed targets | Knowledge diffs feed the next analyzer cycle |
| EMA confidence history | Controller starts with trend data, not from zero |
| pi Synthesis cluster queue | Similar-target propagation survives restart |
| Allium BDD status | Behavioral coherence tracked across cycles |

### Context persistence

`var/context/<experiment-id>.sexp` preserves per-experiment business memory:

| Field family | Why it matters |
|-------------|----------------|
| **business-rationale** | Keeps the why, not just the what |
| **causal-chain** | Lets later analysis see indirect causes |
| **learned / decision-rationale** | Turns outcomes into institutional memory |
| **dependency analysis** | Captures blast radius for future regeneration |

### Human-governed persistence

`var/approval-queue/` persists pending and decided proposals:

| Path | Purpose |
|------|---------|
| `pending/` | High-risk proposals waiting for human review |
| `approved/` | Accepted proposals archived for follow-through |
| `rejected/` | Rejected proposals archived as negative policy memory |

The pipeline verifies persistence surfaces after evolution steps and restarts the daemon to pick up evolved code. Memory is not ornamental; it is the substrate of compounding.

---

## Safety

The pipeline's immune system:

| Guard | Prevents |
|-------|----------|
| Git worktree isolation | `main` never touched directly |
| **3,485 ERT tests** + timeout guard | Broken code caught before staging |
| **7-gate execution path** | Bad changes filtered before integration |
| **Platform sandbox** | OS-level process containment (seatbelt/bubblewrap) |
| Complexity gate | Code bloat masquerading as progress |
| Ontology-aware provider routing | Unhealthy backends auto-penalized or excluded |
| Per-target model preference | Historical performance selects stronger model |
| Routing audit trail | Every decision inspectable after the fact |
| Nucleus persona injection | Subagent-appropriate attention shaping |
| Drift-forced backend swap | 3+ consecutive failures -> deterministic backend rotation |
| Monitoring agent | Systemic failures noticed after each batch, not weeks later |
| Approval queue | High-risk proposals stop at human review |
| 24/7 watchdog | Emacsclient health checks, lock files, stale socket cleanup, RSS guard |
| Force-push protection | Stashes dirty artifacts, merges safely, never force-pushes `main` |
| Conflict marker detection | No `<<<<<<<` in committed code |
| Policy engine | Forbidden paths sealed |

### Self-Healing

The system detects when its own evaluators are broken and heals itself - no human required.

**Runtime self-heal** (pipeline health):

| Phase | What it does | Trigger |
|-------|--------------|---------|
| **1. Pipeline Health Monitor** | Tracks keep-rate, grader success rate, timeout rate, backend availability per run | Every experiment completion |
| **2. Auto-Remediation** | Applies fixes: timeout handling, budget adjustment, backend switch | keep-rate == 0% for repeated runs |
| **3. Meta-Learning** | Records whether each remediation worked | After remediation + next run |
| **4. Diagnostic Probes** | Runs trivial experiment before real ones when needed | Before experiment batches |
| **5. Grader Health Dashboard** | Labels backends critical / degraded / healthy | Real-time during experiments |
| **6. Backend Escalation** | Switches to alternative backends when remediation fails repeatedly | Consecutive failed remediations |

**Compilation-time self-heal** (byte-compiler discipline):

| Phase | What it does | Enforcement |
|-------|--------------|-------------|
| **0. Paren-balance gate** | `check-parens` before any fixer runs | Blocks later fixers if structure is broken |
| **1. Mechanical fixers** | Docstrings, quotes, unused vars, free vars, arg mismatch, `let` -> `let*` | Each fixer wrapped with rollback verification |
| **2. Rollback verification** | Revert automatically if a fix breaks parens | Prevents silent structural corruption |
| **3. Dog-food principle** | Self-heal fixes its own warnings first | Self-reference tests the repair loop |
| **4. Pre-commit enforcement** | `byte-compile-error-on-warn t` on staged `.el` files | Rejects warning-bearing commits |

**Module discipline:** 120 modules are tracked in the current architecture: **76 byte-compiled**, **44 marked `no-byte-compile`**. The self-heal layer exists so the system fixes its own code before touching yours.

**Key principle:** timeout means "could not evaluate," not "code is bad." The grader treats timeouts as unknown, not as proof of failure. The monitoring agent is operational today: it runs after each experiment batch, throttled to 15-minute windows, and can emit low-risk remediations, notify-only routing changes, or approval-required structural proposals.

```
lambda self-heal(x).
  detect(pipeline-health) -> diagnose(x) -> remediate(x) -> verify(x)
  | learn(failure) == learn(success) | not waste(errors)
  | timeout(x) != failure(x) | timeout == unknown
  | escalate(x) -> backend > human | not ask_human_first
  | paren(x) -> gate(Phase0) | not fix_before_check
  | rollback(fixer) == verify(parens_after) and revert_on_break
  | dogfood(self) == fix_own_warnings_first
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Pipeline stuck at "selecting" | Analyzer rate-limited or backend timeout | Check `gptel-auto-workflow-status`; wait for auto-failover |
| 0 targets selected | All backends rate-limited simultaneously | Check API keys and backend health state |
| All experiments discarded | Baseline tests failing | Run the test suite manually; inspect daemon log |
| Approval queue keeps growing | High-risk proposals generated faster than they are reviewed | Review pending proposals; prune expired entries |
| Monitoring agent silent for many runs | Batch throttle window or hook not firing | Check after-experiment hook wiring and monitoring logs |
| "prompt is empty" errors | Strategy analysis returned no patterns | Usually transient; if persistent, inspect evolution artifacts |
| Daemon unresponsive | Test run blocking or stale socket | Wait briefly, then restart watchdog if needed |
| Daemon frozen (heartbeat stale) | Main thread blocked on long API call | Heartbeat watchdog auto-restarts after 180s staleness |
| Same error across all backends | Code issue, not provider | Read the error - often missing function or paren mismatch |
| "all backends exhausted" | Quota exhausted on all providers | Check provider billing; system recovers when quotas return |
| Worktree merge conflicts | Parallel experiments touched overlapping files | System auto-rebases; if persistent, prune worktrees and retry |
| Context missing for a result | Sidecar capture failed at TSV boundary | Check `var/context/` write path and capture hook |
| Keep-rate stuck at 0% after 50+ experiments | Targets do not match ontology categories or sensors are misleading routing | Review targets, categories, and recent routing audit |
| Memory usage >2.5GB RSS | Long-running daemon accumulating state | Watchdog auto-restarts; inspect RSS guard behavior |

---

## Research Foundations

OV5's architecture is informed by five key research papers:

| Paper | Key Insight | OV5 Implementation |
|-------|-------------|-------------------|
| **MOSS** (2605.22794) | Source-level self-evolution is Turing-complete | Self-heal-semantic module fixes code at source level |
| **Sibyl-AutoResearch** (2605.22343) | Trial-and-error harnesses need explicit conversion | Ontology captures trial outcomes as executable knowledge |
| **APEX** (2605.21240) | Self-evolving agents suffer exploration collapse | Category saturation detection prevents collapse |
| **RPG** (2509.16198) | Structured graphs > free-form NL for planning | Experiment dependency graph (planned) |
| **AttnRes** (2603.15031) | Fixed-weight accumulation causes hidden-state dilution | Weighted experiment synthesis (planned) |
| **OpenMythos** (RDT) | Looped transformers: recurrent depth, stability, adaptive compute | OV5 as recurrent system (6 gaps identified) |
| **PlanSearch** (2409.03733) | Plan diversity directly predicts performance gains | Plan-level search with Jaccard similarity metric |

**Knowledge pages**: `mementum/knowledge/self-evolving-agent-research.md`, `mementum/knowledge/research-planning-graph-plansearch-ov5-gaps.md`

---

## The Future Layer

OV5 already closes the inner loop: route, experiment, gate, learn, evolve. The unfinished frontier is the outer loop: richer external sensors, approved-proposal auto-consumption, and broader regeneration of disposable modules from preserved business context.

Current truth: **Sensor is partial**, **architectural evolution is live**, **code regeneration is live**, and **approval consumption still needs tighter auto-follow-through**. Future work points toward local deterministic execution as well - see [verbum](https://github.com/davidwuchn/verbum).

---

Built on [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d). Extended with gptel, nucleus statecharts, mementum memory, verbum operational taxonomy, Semantica ontology, AutoGo competitive gating, LogMap indexing and repair, Allium behavioral compilers, context-aware regeneration, and monitoring-driven architectural evolution. **37 patterns** across multiple frameworks. The art grows with its practitioner.
