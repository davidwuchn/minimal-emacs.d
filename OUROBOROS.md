# Ouroboros: Self-Regulating AI Architecture

> **The snake that researches what to eat, executes what it learned, and feeds outcomes back into its own appetite.**

Built on [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d) + [gptel](https://github.com/karthink/gptel). 3 pipeline runs/day (macOS: 10AM/2PM/6PM; Linux: every 4h) + hourly self-evolution + watchdog every 30min. The snake eating its own tail — every subsystem improves every other subsystem.

---

## The Principle

**Ouroboros.** The snake eating its tail.

```
λ engage(emacs).
  research(external) ⇄ execute(experiment) ⇄ verify(outcome) ⇄ learn(pattern)
  | ∀change: isolated(worktree) ∧ verified(tests) ∧ reviewed(AI)
  | self_referential: the system audits itself using its own ontologies
  | route(ontology) ≡ categorize(target) → rank(backends) by Δ(keep-rate − baseline) ⊗ trend ⊗ confidence
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

Say "Ouroboros" and you mean: the full self-regulating cybernetic architecture.

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
Select target → Categorize → Route backend → Generate hypothesis
      → Run 1940 tests → AI grade → AI review → Merge or learn
          ↓
     Kept? → π Synthesis: semantic cluster → inherit strategy → auto-queue
```

Every experiment is an isolated git worktree. `main` is never touched directly. Six gates stand between a hypothesis and a merge:

| Gate | What it checks | What happens on failure |
|------|---------------|------------------------|
| **Category routing** | Best backend for this target RIGHT NOW? (Δ-from-baseline + trend + confidence) | Routes to strongest current performer; unhealthy backends dropped |
| **Test execution** | Did 2481 tests pass within 1800s? | Experiment discarded, pattern learned |
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

The cycle closes: **kept experiments tell the researcher what to pursue; discarded experiments tell it what to avoid; π Synthesis propagates winning strategies to similar targets without re-researching.** This is the ouroboros — the head eats based on what the tail produced.

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
| | Scoring: 40% delta-from-peers + 30% keep-rate + 20% trend + 10% confidence | Penalty for unhealthy backends (3+ recent errors) |
| | **Smart subagent routing**: all 5 subagent types (researcher, analyzer, executor, grader, reviewer) | Backends ranked by health-weight × historical-keep-rate; quarantined excluded; failures feed back as strikes |
| **π Synthesis** | Kept target → semantic cluster → strategy inheritance | "Which similar files should inherit this winning strategy?" |

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
| **Backend performance analysis** | 1,200+ experiments tracked per backend/model → keep-rate statistics |
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

Backend selection for subagent calls is itself an Ouroboros loop:

```
Subagent call → failure (timeout/rate-limit) → health strike recorded
    → ranked-subagent-backends deprioritizes backend
    → future calls route to healthier backends
    → lambda verification retest → :healthy → strikes cleared
    → backend restored to routing pool
```

Scoring: `health-weight × historical-keep-rate`. Quarantined backends (3+ strikes) excluded. This means the routing learns which backends actually work from real experiment data, not static configuration. The snake's routing eats its own failures.

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
| 1940 tests + 1800s timeout | Broken code caught before staging |
| Ontology-aware provider routing | Ranks backends by delta-from-baseline + keep-rate + trend + confidence; penalizes unhealthy providers |
| Force-push protection | Stashes dirty artifacts, merges origin/main, then pushes; never force-pushes |
| Server socket self-healing | 30s timer recreates lost daemon socket; no SIGKILL restart needed |
| Pipeline state verification | `cross-subsystem-state.json` checked after evolution; daemon restarted to load evolved code |
| Cross-cycle amnesia guard | All hints serialized to JSON with proper keyword keys; EMA history persists across daemon restarts |
| Conflict marker detection | No `<<<<<<<` in committed code |
| 90-minute watchdog | No technique runs indefinitely |
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

**Phase 2 — Verification (active)**
- Subagent call failures feed into persistent health strikes → routing self-tunes
- Backend health tracked across restarts via cross-subsystem-state.json
- P(λ) gating: detect when a backend is *not* running the lambda compiler (hallucination vs. structured computation)

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
