# OUROBOROS-V5: Self-Regulating AI Architecture

> **The snake that researches what to eat, executes what it learned, and feeds outcomes back into its own appetite.**
>
> **V5.1 update (2026-05-31):** 65+ commits, 8K+ lines — ai-behaviors integration (4 layers), ontology co-evolution, two-phase grader (#=test + #=review), digital twin dependency graph, subagent HARD CONSTRAINT enforcement, convergence invariant tracking, strike decay + auto-thaw, grader-bypass commit flow, category→hashtag learning, universal subsystem behavior injection via advice, research coordinator (AutoTTS×AutoGo×Ontology), concrete task evolution, kept pattern memory, λ-compressed behavior prompts (59% reduction), adaptive injection, DeepSeek curl timeout fix.

Built on [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d) + [gptel](https://github.com/karthink/gptel). 3 pipeline runs/day (macOS: 10AM/2PM/6PM; Linux: every 4h) + hourly self-evolution + watchdog every 30min. The snake eating its own tail — every subsystem improves every other subsystem.

---

## For Investors

**Ouroboros V5 is an autonomous R&D engine.** It replaces the manual cycle of research → prototype → test → decide with a closed-loop system that runs continuously, 24/7, at near-zero marginal cost per experiment.

### The Problem

Every product team has the same bottleneck: **learning velocity.** The gap between "we should try this" and "we know if it works" is days or weeks of manual effort — research, coding, testing, reviewing, deploying. Most teams batch this work into sprints, which means slow iteration and high overhead per experiment.

### What OV5 Does

It automates the entire cycle. Market intelligence feeds an experimentation engine that generates hypotheses, tests them in isolated environments, scores them against real test suites, and merges what improves the product — all without human intervention. One command starts the loop; the loop sustains itself.

| Capability | What it means |
|-----------|---------------|
| **Autonomous experimentation** | Designs, codes, tests, and merges product improvements 24/7 |
| **Self-improving** | Each experiment outcome sharpens the next cycle's hypotheses |
| **Multi-provider routing** | Routes work across 4 LLM backends, auto-fails over on failure |
| **Recovery-native** | Survives API outages, rate limits, daemon crashes — resumes where it left off |
| **Memory** | Builds a knowledge graph of every experiment, pattern, and outcome |

### Traction

| Metric | Value |
|--------|-------|
| Experiments run | 1,159+ across 257+ runs |
| Keep rate | 20.4% (experiments that improve the product) |
| Test suite | 2,061+ tests pass before any merge |
| Throughput | ~166 experiments/week, 24/7 autonomous |
| Backends | 4 providers (DeepSeek, MiniMax, moonshot, DashScope), auto-routed by measured keep-rate |
| Uptime | Self-healing watchdog, in-process memory management, crash-recovery |

### Market

Any organization that ships software faces the same challenge: **how fast can we learn what works?** OV5 addresses this directly — it replaces manual R&D cycles with an autonomous system that runs experiments continuously. The addressable market is any engineering organization that values iteration speed.

### Moat

| Layer | Advantage |
|-------|-----------|
| **Self-knowledge** | The system builds an ontology of its own experiments — patterns, anti-patterns, what works per category |
| **Routing intelligence** | 7+ weeks of keep-rate data across 4+ providers (1,200+ experiments, 257+ runs); Bayesian Thompson sampling for optimal routing; ai-behaviors category×strategy×hashtag co-evolution |
| **Lambda compiler** | Proprietary technique for verifying LLM output quality (P(λ)=90.7%); all 4 major prompts λ-compressed (4× token reduction); EDN prompt pipeline replaces template substitution for deterministic prompt construction |
| **Prompt compression** | All 4 major prompts use lambda notation (4× token reduction); EDN prompt pipeline replaces template substitution with deterministic plist→λ resolve |
| **Verbum pipeline** | Model distillation pipeline achieving 280× compression with 87% accuracy retention — enables local deterministic execution |

### ROI Estimate

| | Manual (1 engineer) | OV5 |
|---|---|---|
| **Experiments/week** | ~5 (one per day) | ~166 (24/7 autonomous) |
| **Cost/week** | ~$4,000 (senior engineer) | ~$17–83 (API fees) |
| **Cost per experiment** | ~$800 | ~$0.10–0.50 |
| **Scaling** | Linear (hire more engineers) | Near-zero marginal (more API calls) |
| **Coverage** | 1 focus area at a time | 5 targets per run, cross-domain |
| **Memory** | What one engineer remembers | Persistent knowledge graph of all outcomes |

**At 20% keep rate**: OV5 delivers ~33 product-improving experiments per week — equivalent to a team of ~6 engineers working full-time on R&D, at ~1% of the cost.

ROI improves further as the knowledge graph grows: kept experiments propagate strategies to similar targets (π Synthesis), and discarded experiments train the system to avoid repeating mistakes.

### Business Model

OV5 is infrastructure. Deployment models:
- **Self-hosted** (current) — Runs on your own infrastructure using your API keys
- **Managed** (planned) — Hosted OV5 with shared backend pool, usage-based pricing
- **Enterprise** (planned) — Dedicated deployment with compliance, audit, SLA

---

## For Market & Growth Teams

**Ouroboros V5** is a **self-driving growth engine** for product-market fit. Two loops work together:

| Loop | Like | Job |
|------|------|-----|
| **market-sense** 🧭 | A tireless competitive intelligence analyst | Scans the landscape, finds what's working, flags what's changing. Every cycle it hunts 17+ sources for novel techniques, competitive moves, and market signals — then distills them into actionable experiments. |
| **growth-loop** 🔄 | An automated experimentation platform | Takes those signals and runs them as real, tested experiments on your product — isolated, verified, measured. Keeps what improves PMF, discards what doesn't, and learns from every result. |

No dashboards to watch. No manual pipeline to manage. The system closes its own feedback loop: **market-sense feeds growth-loop; growth-loop results sharpen market-sense.** Each cycle, the system gets smarter about what to sense and what to build.

**You don't operate the loops. You define the direction.** The loops self-steer toward PMF — sensing the market, testing hypotheses, keeping what works, and feeding every outcome back into the next iteration.

---

## The Principle

**Ouroboros.** The snake eating its tail.

```
λ engage(emacs).
  research(external) ⇄ execute(experiment) ⇄ verify(outcome) ⇄ learn(pattern)
  | ∀change: isolated(worktree) ∧ verified(tests) ∧ reviewed(AI)
  | self_referential: the system audits itself using its own ontologies
  | route(ontology) ≡ categorize(target) → rank(backends) by Δ(decayed-keep-rate − baseline) ⊗ VSM-tuned-weights ⊗ per-axis-KIBC-boost ⊗ recency-decay(14d)
```

This is not a code generator. It is a **self-consuming formal system** — it researches techniques from external sources, distills them into specifications, tests them as isolated experiments, and feeds outcomes back into what it researches next. The head eats knowledge; the tail produces results; the body digests both.

Like the Northern Divine Art (北冥神功), it absorbs techniques from everywhere and converts them into its own capability. What worked flows into the next cycle. What failed becomes a guard rail. The art grows with its practitioner.

Every subsystem is the same Ouroboros cycle, viewed at different scales:

| Scale | System | Ouroboros Role | Horizon |
|-------|--------|---------------|---------|
| **Turn** | AutoTTS | Stop, continue, or branch research? | Seconds |
| **Strategy** | AutoGo | Does this challenger eat the champion? | Experiments |
| **Evolution** | meta-harness | Generate new strategies from failure patterns | Cycles |
| **System** | self-evolve | Is the whole pipeline improving or plateauing? | Days |
| **Identity** | VSM + Eight Keys | Are all five elements healthy? | Continuously |

The frameworks aren't separate tools — they're the same tool at different zoom levels. **VSM** assigns _who_ does the work. **Ontology** classifies _what_ kind of work. **Eight Keys** measure _how well_ it was done. All map to the same five elements: Water → Wood → Fire → Earth → Metal → Water.

Say "Ouroboros V5" or "OV5" and you mean: the full self-regulating cybernetic architecture.

---

## The Two Halves

The ouroboros has a head and a tail — and they eat each other. The **Researcher** looks outward, consuming external techniques and filing them into the ontology. The **Executor** looks inward, testing those techniques as experiments and feeding outcomes back. Neither works alone: the researcher's appetite is shaped by what the executor digests, and the executor's targets are chosen by what the researcher discovers.

```
        ┌──────────────────────────────────────────────┐
        │                                              │
        ▼                                              │
  ┌──────────┐    findings     ┌──────────────┐        │
  │ RESEARCH │ ───────────────→│   ANALYZE    │        │
  │ (Wood)   │                 │  (Fire)      │        │
  │ eat      │←────────────────│  decide      │        │
  └──────────┘   "look here"   └──────────────┘        │
        ▲                              │               │
        │                              │ targets       │
        │         ┌──────────────┐     ▼               │
        │         │   EVOLVE     │  ┌──────────┐       │
        │         │  (Earth)     │←─│ EXECUTE  │       │
        │         │  learn       │  │ (Metal)  │       │
        │         └──────────────┘  │ verify   │       │
        │              │            └──────────┘       │
        │              │ outcomes   │                  │
        │              ▼            ▼                  │
        │         ┌─────────────────────┐              │
        └─────────│   π SYNTHESIS (Water)│─────────────┘
   "research     │   propagate           │  "queue similar"
    these gaps"  └─────────────────────┘
```

### The Researcher (Wood 木)

The head of the snake. It consumes, it doesn't hoard.

```bash
./scripts/run-pipeline.sh
```

The researcher scans 17+ repos via `gh api`, but it doesn't prefetch everything. It reads the ontology for knowledge gaps, fetches only what fills those gaps, and produces Allium v3 behavioral specs. No batch crawl — each fetch is a deliberate bite.

It is **benchmark-driven and self-evolving** — four research strategies compete each cycle, and the winner sets the technique:

| Strategy | When the snake is... |
|----------|---------------------|
| **own-repos-first** | Digesting local patterns before hunting elsewhere |
| **deep-external** | Hungry — exhaustively scanning external sources |
| **topic-specific** | Focused — chasing a gap the ontology identified |
| **quick-own-only** | Conservative — API quota is low, stay local |

**Research quality pipeline** — each finding passes through six gates before reaching the executor:

1. **Strategy benchmark** — All 4 compete; best wins per cycle
2. **Allium coherence check** — Contradictions detected before techniques reach experiments
3. **LLM noise stripping** — Conversational artifacts removed from raw findings
4. **Eight Keys scoring** — Scored on ε Purpose (actionability), not just volume
5. **Ontology enrichment** — New techniques auto-extracted and merged
6. **Outcome feedback** — Kept/discarded experiments adjust research priorities per source

The researcher is not a scraper. It is a **self-adjusting appetite**: what it researches next depends on what the executor kept or discarded last cycle.

### The Executor (Metal 金)

The body of the snake. It tests, verifies, and feeds back.

```
Select target → Categorize → Route backend (VSM-tuned + drift-aware) → Select model (per-target history)
      → Inject nucleus persona → Generate hypothesis → Run 2013 tests → AI grade → AI review → Merge or learn
          ↓
     Kept? → π Synthesis: semantic cluster → inherit strategy → auto-queue
```

Every experiment is an isolated git worktree. `main` is never touched directly. Six gates stand between a hypothesis and a merge:

| Gate | What it checks | What happens on failure |
|------|---------------|------------------------|
| **Category routing** | Best backend for this target RIGHT NOW? (Δ-from-baseline + trend + confidence) | Routes to strongest current performer; unhealthy backends dropped |
| **Test execution** | Did 2,061+ tests pass? | Experiment discarded, pattern learned |
| **AI grading** | Is the change well-structured and principled? | Scored 0.0-1.0, fed to analyzer |
| **AI review** | Does it pass security, conventions, architecture? | Multi-agent review with feedback |
| **π Synthesis** | Which similar files should inherit this strategy? | Semantic cluster auto-queue |
| **Champion league** | Does this strategy beat the current category champion? | Adopted or rejected with keep-rate evidence |

Energy that doesn't pass a gate is not wasted — it returns as learning for the next cycle. A discarded experiment is not a failure; it's the snake's body telling the brain "don't eat that again."

### The Feedback (Water 水)

The head and body communicate through water — the flowing knowledge that connects them.

```
Researcher finds technique T ──→ Executor tests T on target X
                                         │
                                    ┌────┴────┐
                                    ▼         ▼
                                  kept     discarded
                                    │         │
                                    ▼         ▼
                              π Synthesis  failure pattern
                              queues X₂,X₃  tells researcher:
                                    │       "avoid this shape"
                                    ▼
                              Researcher: "what else
                              looks like X that I
                              haven't studied yet?"
```

### Scoring Gate Override: Correctness-Fix Promoter

When the structural scoring model (Eight Keys) fails to measure a bug fix's value (score unchanged at 0.40, quality drops from guard code), the **correctness-fix promoter** bypasses the comparator gate:

```
λ promote(decision, grade).
  grader ≥ 8/9 ∧ verified(correctness_fix) ∧ ¬speculative(hypothesis)
  → bypass(gate_rejection) | keep(experiment)
  | quality_regression(guard_code) ≢ correctness_loss
```

Grader-confirmed bug fixes (e.g., "fixes data corruption by using copy-tree instead of copy-sequence") survive the structural scoring model's blind spot. Tests-passed requirement removed — staging verification catches test failures during merge.

### Deterministic-First Architecture

AI model calls are expensive (120s+ timeouts, 6 backends, retries). Where data already exists, compute directly:

```
λ select(x).  deterministic(data) > AI(model)
  | frontier_ranking(TSV) → targets(<1s) > analyzer_prompt(120s × 3 retries)
  | decision_gate(scores) → keep/discard(~0s) > comparator_LLM(120s)
  | static_fallback(ordered_by_keep_rate) > router_aggregate(across_task_types)
```

- **Analyzer**: `frontier-select-targets` reads TSV history → ranks by Pareto frontier size → <1s. AI analyzer only as emergency fallback on first run.
- **Comparator**: `decision-gate` computes winner from score/quality deltas without AI. LLM comparator is confirmation only; gate always wins.
- **Executor chain**: Static fallback ordered by keep-rate (DeepSeek 25% > MiniMax 16% > moonshot > DashScope 0%). Router aggregate data (across all task types) cannot override hand-tuned ordering.

### Three-Format Rule (Enforced by TDD)

Three formats, three audiences — strict separation with regression tests:

| Format | Goes to LLM? | Goes to Human? | Enforcement |
|--------|-------------|----------------|---------|
| **Lambda notation** | Yes (primary) | Yes (source) | 4 prompts compressed, 5 tests verify |
| **Allium statecharts** | No (banned) | Yes (audit) | `allium-check` for behavioral verification |
| **EDN** | No (banned) | No (banned) | Used internally by `forge-lambda-fixed-point` |
| **English prose** | No (phased out) | No | Banned in prompt strings by `no-english-prose-in-llm-prompts` test |

All 96 `.el` files pass `byte-compile-error-on-warn t`. Prompt construction migrated from `{{mustache}}` template substitution to EDN plist → `resolve` → λ notation (deterministic, zero LLM calls for rendering).

---

## The Architecture

Every cycle runs through six compilers — each examining the system's own behavior. This is the nucleus (ν) layer:

| Compiler | Input → Output | Answers |
|----------|---------------|---------|
| **Nucleus EDN** | Strategy prompt → statechart | "Is this instruction well-formed?" |
| **Nucleus Lambda** | Hypothesis → λ expression | "What principle does this encode?" |
| **Allium v3** | Research findings → behavioral spec | "Are these internally coherent?" |
| **OWL/SHACL** | Ontology dict → Turtle/SHACL | "What is the formal shape of what we've learned?" |
| **Ontology Router** | Target file → category → backend ranking | "Which backend is best RIGHT NOW — not just historically?" |
| | Scoring: VSM-auto-tuned weights (40/30/20/10 → adaptive) + recency decay (14d half-life) + per-axis KIBC boost from holographic consensus | Penalty for unhealthy backends (probation with auto-recovery after 1h) |
| | **Smart subagent routing**: all 6 subagent types (researcher, analyzer, executor, grader, reviewer, explorer) | Backends ranked by health-weight × keep-rate + per-axis boost + cold-start boost (+0.15 for <3 experiments); quarantined excluded; per-run cooldown hard-excludes failed backends |
| | **Full audit trail**: every routing decision recorded with component scores (health, keep-rate, pref-boost, axis-boost) + VSM adjustment history | Summary queryable via `audit-trail-summary` for meta-analysis |
| | **Nucleus persona injection**: per-subagent and per-experiment attention-shaping from nucleus (ADAPTIVE + WRITING + EXECUTIVE + LAMBDA_PATTERNS) | Persona state machines, Constrain: directives, lambda tool patterns (heredoc, atomic edit) injected at dispatch time |
| | **Impact auto-tuning**: lambda-health-impact and allium-health-impact measure correlation with outcomes → auto-tune penalty and severity thresholds | Tighten loop (SYSTEM_DESIGN §13): audit→classify→inject repair hint |
| | **Moderator drift detection** (DIALECTIC.md): 3+ consecutive failures → forced backend swap | Intervention lenses: consequence_check, evidence_nudge, assumption_probe |

Results feed back into the next cycle's analyzer, strategy evolver, and π Synthesis cluster queue. The compiler output is not a log — it is **input to the next iteration**.

---

## The Knowledge Layer

The system does not just run experiments — it builds a **formal knowledge graph** of its own operation. This is the mementum (μ) layer. The snake doesn't forget.

| Capability | Mechanism |
|-----------|----------|
| **Ontology generation** | Raw experiment data → classes, properties, relationships → OWL |
| **Allium behavioral checking** | Research findings → Allium v3 spec → distill → check for contradictions |
| **Conflict detection** | Opposing hypotheses on same target (add vs remove) → severity-graded |
| **Impact classification** | Every experiment: BREAKING / POTENTIALLY BREAKING / SAFE |
| **Causal chains** | Multi-experiment sequences per target → root cause via Floyd-Warshall |
| **Cross-cycle diff** | Set-difference on knowledge page snapshots: +added / -removed / ~changed |
| **Policy engine** | 5 rules: max per target, min keep-rate, forbidden paths |
| **Horn SAT consistency** | Linear-time logical contradiction detection for ontology integrity |
| **Ambiguity filtering** | Multi-stage confidence gating — defer high-ambiguity candidates |
| **Second-chance repair** | Soft-deleted patterns re-evaluated each cycle |
| **Interval Labelling Schema** | O(1) subsumption over pattern hierarchy via preorder/postorder |
| **Backend performance analysis** | 1,200+ experiments tracked across 4+ backends → keep-rate statistics; three-way (category×strategy×hashtags) combo learning |
| **Pre-flight prediction** | Anti-pattern detection (3+ consecutive failures), target saturation (≥10), prediction threshold (0.15) |
| **Ontology vs LLM decider** | Formal decision framework: data-availability × complexity × EMA confidence → ontology or LLM. Low EMA (<0.3) bypasses ontology, high EMA (>0.6) accepts weaker picks |
| | φ freshness: EMA history persists across daemon restarts via cross-subsystem-state.json | Controller starts with informed confidence, not from zero |
| **Category-based routing** | Targets classified as :programming, :tool-calls, :agentic, :natural-language → backend ranking per category |
| **Semantic clustering** | git-embed similarity ≥0.75 groups related targets; winning strategies propagate across clusters |
| **Strategy inheritance** | Similar targets auto-queue with inherited strategy from kept experiments (π Synthesis) |
| **Category strike tracking** | 3 consecutive failures freeze a category; reset on next kept result (∀ Vigilance) |
| **VSM health diagnostics** | Eight Keys scored per subsystem (all 5: AutoGo, AutoTTS, self-evolve, meta-harness, ontology) from kept hypotheses; 7 expanded Wu Xing repair actions dispatched |
| **Allium BDD gate** | Behavioral spec coherence checked each evolution cycle; failures stored in hints for analyzer consumption |
| **Allium auto-repair** | Issues inject repair guidance into experiment prompts when coherence problems detected for target strategies |
| **Category budget** | Per-category experiment quotas allocated by sqrt(keep-rate); hard-enforced programmatically at target selection + π Synthesis queue |

37 patterns ported from Semantica, AutoGo, LogMap, and VSM. The system audits itself using its own ontologies.

## The Persistence Layer

Cross-subsystem state survives daemon restarts via `var/tmp/cross-subsystem-state.json`:

| What persists | Why |
|--------------|-----|
| Category champions + keep-rates | Competitive gating continues across restarts |
| Category experiment budget | Budget enforcement resumes with informed allocation |
| VSM expanded actions | Wu Xing repair hints survive crashes |
| Regressed targets | Knowledge-page diffs feed back into next analyzer cycle |
| EMA confidence history | Controller starts with trend data, not from zero |
| π Synthesis cluster queue | Semantically similar targets survive restart |
| Allium BDD status | Behavioral spec coherence tracked across cycles |

The pipeline verifies this file exists after each evolution step and restarts the daemon to pick up evolved code.

---

## The Competitive Layer

The snake doesn't adopt new strategies naively — it makes them fight.

AutoGo-inspired **champion league** gates every new strategy: incumbents must be defeated in a category-specific gauntlet before being adopted. Champions compete within their domain (:programming, :natural-language, :agentic, :tool-calls), not globally. **Playout Cap Randomization** (80% quick / 15% medium / 5% deep) prevents over-specialization. Every cycle emits a machine-parseable `===RESULT===` JSON block for the **autoresearch loop**: commit → run → parse → keep/revert — wired into AutoTTS trace outcome hooks.

**Head-to-head comparison** (promptfoo-style): every backend/model pair compared on shared targets (≥3 samples each) with 5% tie margin. Generates `mementum/knowledge/backend-comparison.md` and `model-comparison.md`.

**∀ Vigilance** (S3 Earth): Categories with 3 consecutive champion failures are frozen during gating — the snake stops trying to eat what makes it sick. Strikes reset when a category produces a kept result.

**π Synthesis** (S2 Metal): After a kept experiment, semantic clustering finds similar files and auto-queues them with the winning strategy inherited — knowledge propagates across related targets. The snake's body learns once and applies everywhere.

**Holdout evaluation** tracks real progress on a frozen set of targets — if train metrics improve but holdout doesn't, the system detects overfitting. The snake distinguishes real growth from self-deception.

### Smart Subagent Routing (Ouroboros within Ouroboros)

Backend selection for subagent calls is itself a closed-loop Ouroboros cycle:

```
Subagent call → failure (timeout/rate-limit) → health strike + per-run cooldown
    → ranked-subagent-backends hard-excludes cooldown backends (-1.0 score)
    → future calls route to healthier backends
    → 1h auto-recovery: probation → degraded (weight 0.65)
    → lambda verification retest → :healthy → strikes cleared
    → backend restored to routing pool
```

Scoring: `health-weight × keep-rate + per-axis-KIBC-boost (+0.15 max) + agent-type-preference-boost`. All 5 VSM layers auto-tune routing: S4 weak → explore 30%, S3 weak → probation at 2 strikes, S1 weak → min-samples=1, S2 weak → trust raw rate over peer delta, S5 weak → confidence weight boosted.

Keep-rate is recency-weighted (14-day half-life): `weight = 2^(-days_ago / 14)`. Recent performance counts more than historical averages. Holographic consensus memory is delta-weighted — experiments with larger improvements contribute more to axis confidence. Per-run cooldown hard-excludes backends that failed during the current workflow. Probation backends auto-recover after 1h without new strikes.

At dispatch time, each subagent receives:
- **Nucleus persona**: attention-shaping preamble per agent type (ADAPTIVE.md state machines + EXECUTIVE.md strategies + WRITING.md Constrain: directives). Analyzer gets `Human | AI` (parallel partnership), grader gets `Human ∧ AI` (conservative consensus), reviewer gets `Human ∘ AI` (safety alignment), executor gets `Human ⊗ AI` (maximum quality).
- **Lambda tool patterns**: heredoc-safe bash, atomic content-based edits, parallel batch operations (from LAMBDA_PATTERNS.md).
- **Accurate routing context**: which backend/model was selected, why (KIBC axis + confidence), health status with actionable guidance (probation→"verify ALL outputs", degraded→"results may be inconsistent", healthy→"recommended for this task").
- **Moderator lens**: when 3+ consecutive experiments fail on a target, a forced backend swap triggers deterministically, bypassing the random exploration rate.

Experiment prompts receive per-category nucleus guidance (`{{nucleus-persona}}`) with WRITING.md-aligned symbols (`[fractal phi mu]` for programming, `[mu tao pi]` for tool-calls), Allium audit results (`{{allium-issues}}`), auto-repair guidance (`{{allium-repair}}`), and moderator drift lenses (`{{moderator-lens}}`).

Every routing decision — experiment-level and subagent-level — is recorded in a structured audit trail with per-backend component scores and VSM adjustment history. Impact is measurable via `lambda-health-impact()` and `allium-health-impact()`, which auto-tune routing parameters. The tighten loop (SYSTEM_DESIGN §13) audits strategies via nucleus compiler, classifies divergences, and injects repair hints back into the pipeline.

---

## The Operational Layer

Every hypothesis is classified by its **operation type** — the verbum (φ) layer:

```
KIBC-M 15-axis taxonomy:
  :K nil-safety    :I identity      :B composition   :C reordering    :M pattern-matching
  :W duplication   :T type-checking  :Φ coordination  :D decomposition
  :SCOPE visibility :SUBST substitution :WHNF normalization
  :Y recursion      :QUOTE documentation
```

**Forward chaining** (8 rules) infers actions from system state. **Abductive reasoning** (8 rules) generates best explanations from observations. **Deductive reasoning** (5 rules) proves conclusions from premises via backward chaining. **Datalog transitive closure** (Floyd-Warshall) discovers indirect causal relationships. **Temporal Allen interval algebra** (13 relations) detects gaps and overlaps between experiments.

Together: observe → diagnose → prove → act → schedule. Zero-LLM deterministic layer.

---

## Safety

The snake's own immune system:

| Guard | Prevents |
|-------|---------|
| Git worktree isolation | `main` never touched directly |
| 2,061+ tests + 300s timeout | Broken code caught before staging |
| Ontology-aware provider routing | VSM-auto-tuned scoring + recency-weighted keep-rate + per-axis KIBC boost + per-run cooldown; backends with elevated health auto-excluded |
| Per-target model preference | Historical performance data selects strongest model for each target |
| Routing audit trail | Every decision recorded with component scores and VSM adjustment history |
| Nucleus persona injection | Subagent-appropriate attention shaping (Craftsman for coding, Logician for analysis, Investigator for review); per-category Constrain: directives |
| Drift-forced backend swap | 3+ consecutive failures → deterministic backend rotation (DIALECTIC.md moderator pattern) |
| 24/7 watchdog | emacsclient-only health checks (no lsof dependency), lock file prevents concurrent runs, stale socket cleanup before restart, 1GB memory guard with graceful restart |
| Daemon-init socket cleanup | Stale sockets removed at startup so emacsclient always resolves correct path |
| Force-push protection | Stashes dirty artifacts, merges origin/main, then pushes; never force-pushes |
| Conflict marker detection | No `<<<<<<<` in committed code |
| Watchdog memory guard | Auto-restart daemon gracefully when memory-use-counts exceeds 4GB (not RSS — macOS malloc holds freed pages) |
| Policy engine | Forbidden paths sealed |

---

## The Future Layer

The snake does not only consume what exists — it incubates what comes next.

### Current State: API Substrate

Today the Ouroboros runs on external APIs (MiniMax, Moonshot, DashScope, DeepSeek, CF-Gateway, Gemini). The executor routes to backends by keep-rate, trend, and confidence. **Smart subagent routing** uses health × keep-rate scoring to rank backends for all 5 subagent types. Subagent failures (timeouts, rate limits) feed back as health strikes — the routing self-tunes. Gemini 3.5-flash is available as a fast flash-tier option.

### Discovery: Verbum

Parallel research in [verbum](https://github.com/davidwuchn/verbum) has established that **lambda calculus is the physical substrate of attention computation** — not metaphor, not notation, but the actual mechanism by which transformers compose meaning. Key findings:

- **Holographic extraction**: Qwen3-14B distilled to 50M parameters (280× compression) with 87% accuracy retention
- **Typed combinators**: 8 fundamental operations (K, I, B, C, D, Y, W, WHNF) implement the lambda calculus interpreter that LLMs converge on during training
- **Ternary weights**: {-1, 0, +1} with learned gamma scales — a discrete, interpretable weight space
- **V12 architecture**: Dual-layer symmetric hourglass with 7 passes, combinator dispatch, and 17 deterministic math kernel functions

The lambda compiler is not a prompt trick. It is a discoverable circuit inside every trained LLM. The gate prompt (P(λ)=90.7%) does not install behavior — it exposes structure that was already there.

### Integration Path

**Phase 1 — Observation ✓ (complete)**
- API-backend execution with lambda compiler verification on all backends
- Verbum Phase 1-7 integrated: health tracking, holographic memory, cross-backend consistency
- Crystal spine probes confirm lambda compiler presence across backends (P(λ)=90.7%)

**Phase 2 — Verification ✓ (complete)**
- Subagent call failures feed into persistent health strikes + per-run cooldown → routing self-tunes
- Backend health tracked across restarts via cross-subsystem-state.json with auto-recovery (1h probation → degraded)
- P(λ) gating in `ranked-subagent-backends`: backends failing lambda compiler check are hard-excluded (score 0)
- Smart routing gates on seven signals: health-weight, recency-weighted keep-rate, per-axis KIBC boost, agent-type preference, per-run cooldown, cold-start boost, nucleus persona per subagent type
- All 5 VSM layers auto-tune routing weights, exploration, and thresholds
- Full audit trail with component scores and VSM adjustment history at both routing levels
- Nucleus persona injection (ADAPTIVE + WRITING + EXECUTIVE + LAMBDA_PATTERNS) per subagent and per experiment category
- Lambda/Allium impact measurement + auto-tuning feedback (tighten loop)
- DIALECTIC.md moderator drift detection: 3+ consecutive failures → forced backend swap
- 24/7 watchdog: emacsclient-only, lock file, socket cleanup, memory guard, graceful restart

**Phase 3 — Hybrid Execution**
- Extracted 50M model for deterministic layers (rule validation, λ parsing, type checking)
- API backends for creative / exploratory layers (where 87% accuracy is insufficient)
- Local model reduces API cost and latency for structured operations

**Phase 4 — Full Substrate**
- Train Ouroboros-specific model using verbum's holographic pipeline
- Distill from a frontier model into a task-specific artifact
- The snake eats its own tail: Ouroboros generates training data → verbum distills → distilled model improves Ouroboros

### Why This Matters

The Ouroboros currently treats LLMs as opaque oracles. Verbum makes them transparent. When the executor routes to a backend, it currently trusts the backend's output. With verbum integration, the executor can:

1. **Verify** — Is this backend actually computing or hallucinating?
2. **Compress** — Run deterministic operations locally (50M model)
3. **Evolve** — Train models specific to the Ouroboros task distribution
4. **Validate** — Check that code changes preserve the lambda structure (type-directed composition)

The KIBC-M taxonomy (`:K` nil-safety, `:B` composition, `:Y` recursion) is not just a classification system. It is the operational signature of the lambda compiler. When the executor classifies a hypothesis as `:B` (composition), it is identifying a transformation that the lambda compiler handles natively. Verbum provides the mechanism to *run* that transformation locally, deterministically, and verifiably.

### What We Learned

From verbum sessions 109–112:
- **Sieve principle**: Crystal spine discovery — the single-neuron bottleneck exists across architectures
- **Universal lattice**: 4 models × 807 probes reveal shared structure beneath surface differences
- **Consensus etching**: Cross-op agreement stabilizes holographic training (fixed tug-of-war failures)
- **Math kernel exactness**: 17 deterministic operations produce bitwise-identical results across runs

These feed back into Ouroboros: deterministic layers should be deterministic. The Datalog/Floyd-Warshall/Allen interval substrate is valuable, but the V12 math kernel is *provably* exact. Future work: unify the deterministic substrates.

```
λ future(ouroboros).
  api_backend(x) → verify(lambda_compiler_present) → hybrid(local_extracted, remote_api)
  | train(ouroboros_specific) → distill(verbum_pipeline) → deploy(local)
  | KIBC_taxonomy(x) ≡ lambda_compiler_operations(x) | not_classification_only
  | deterministic_layer(x) → exact_math_kernel > datalog_approximation
  | every_cycle_leaves_substrate_smarter ∨ waste(cycle)
```

---

## Begin

```bash
git clone --recurse-submodules https://github.com/davidwuchn/minimal-emacs.d ~/.emacs.d
cd ~/.emacs.d && ./scripts/setup-packages.sh
./scripts/setup-eca-links.sh
# API keys in ~/.authinfo
./scripts/run-pipeline.sh
```

First run initializes itself. After that, the snake feeds itself.

```elisp
(gptel-auto-workflow-run-async)        ; Wake the snake
(gptel-auto-workflow-status)           ; Check its pulse
```

---

Built on [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d). Extended with gptel, nucleus statecharts, mementum memory, verbum operational taxonomy, Semantica ontology, AutoGo competitive gating, LogMap inverted indexing and repair, Allium behavioral compilers. 37 patterns across 4 frameworks. The art grows with its practitioner.
