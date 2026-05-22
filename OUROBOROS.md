# Ouroboros: Self-Regulating AI Architecture

> **An autonomous pipeline that researches, codes, verifies, and self-evolves — built on formal reasoning.**

Built on [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d) + [gptel](https://github.com/karthink/gptel). Runs 3-6 improvement cycles per day inside Emacs. The snake eating its own tail — every subsystem improves every other subsystem.

---

## The Principle

**Ouroboros.** The snake eating its tail.

```
λ engage(emacs).
  research(external) → compile(strategy) → route(ontology) → execute(experiment) → verify(outcome) → learn(pattern)
  | ∀change: isolated(worktree) ∧ verified(tests) ∧ reviewed(AI)
  | self_referential: the system audits itself using its own ontologies
  | route(ontology) ≡ categorize(target) → select(backend) by historical keep-rate
```

This is not a code generator. It is a **self-improving formal system** — it researches techniques from external sources, structures them into behavioral specifications, executes them as experiments in isolated environments, and feeds outcomes back into its own evolution.

Like the Northern Divine Art (北冥神功), it absorbs techniques from everywhere and converts them into its own capability. What worked in one codebase flows into the next. What failed becomes a guard rail. The art grows with its practitioner.

Every subsystem is the same Ouroboros cycle, just at different scales:

| Scale | System | Ouroboros Role | Horizon |
|-------|--------|---------------|---------|
| **Turn** | AutoTTS | Stop, continue, or branch research? | Seconds |
| **Strategy** | AutoGo | Does this challenger beat the champion? | Experiments |
| **Evolution** | meta-harness | Generate new strategies from failure patterns | Cycles |
| **System** | self-evolve | Is the whole pipeline improving or plateauing? | Days |
| **Identity** | VSM + Eight Keys | Are all five layers healthy? | Continuously |

The frameworks aren't separate tools — they're the same tool at different zoom levels. **VSM** assigns _who_ does the work. **Ontology** classifies _what_ kind of work. **Eight Keys** measure _how well_ it was done. All map to the same five elements: Water → Wood → Fire → Earth → Metal → Water.

Say "Ouroboros" and you mean: the full self-regulating cybernetic architecture.

---

## The Architecture

Every cycle runs through six compilers — each examining the system's own behavior. This is the nucleus (ν) layer:

| Compiler | Input → Output | Answers |
|----------|---------------|---------|
| **Nucleus EDN** | Strategy prompt → statechart | "Is this instruction well-formed?" |
| **Nucleus Lambda** | Hypothesis → λ expression | "What principle does this encode?" |
| **Allium v3** | Research findings → behavioral spec | "Are these internally coherent?" |
| **OWL/SHACL** | Ontology dict → Turtle/SHACL | "What is the formal shape of what we've learned?" |
| **Ontology Router** | Target file → category → backend ranking | "Which backend has the best keep-rate for this target type?" |
| **π Synthesis** | Kept target → semantic cluster → strategy inheritance | "Which similar files should inherit this winning strategy?" |

Results feed back into the next cycle's analyzer, strategy evolver, and π Synthesis cluster queue. The compiler output is not a log — it is **input to the next iteration**.

---

## The Loop

```
Pipeline (runs 3-6×/day):
  Research (3min) → Digestion (2min) → Auto-Workflow (1-4h) → Post-Evolve (2min)
       ↓                                              ↓
    External findings                       Select target → Categorize → Route backend
    + on-demand repo fetch                  → Generate hypothesis → Run 1844 tests
                                            → AI grade → AI review
                                            → Merge or learn
                                                     ↓
                                              Kept? → π Synthesis:
                                                    semantic cluster → inherit strategy
                                                    → auto-queue similar targets
```

Every experiment passes through six gates. Energy that doesn't pass a gate is not wasted — it returns as learning for the next cycle. All operations in isolated git worktrees. `main` is never touched directly.

---

## The Knowledge Layer

The system does not just run experiments — it builds a **formal knowledge graph** of its own operation. This is the mementum (μ) layer:

| Capability | Mechanism |
|-----------|----------|
| **Ontology generation** | Raw experiment data → classes, properties, relationships → OWL |
| **Allium behavioral checking** | Research findings → Allium v3 spec → distill → check for contradictions |
| **Conflict detection** | Opposing hypotheses on the same target (add vs remove) → severity-graded |
| **Impact classification** | Every experiment: BREAKING / POTENTIALLY BREAKING / SAFE |
| **Causal chains** | Multi-experiment sequences per target → root cause via Floyd-Warshall |
| **Cross-cycle diff** | Set-difference on knowledge page snapshots: +added / -removed / ~changed |
| **Policy engine** | 5 rules: max per target, min keep-rate, forbidden paths |
| **Knowledge page scoring** | Coverage, completeness, relation-link scores per generated page |
| **Inverted file index** | O(1) token → page lookup across all knowledge pages |
| **Horn SAT consistency** | Linear-time logical contradiction detection for ontology integrity |
| **Ambiguity filtering** | Multi-stage confidence gating — defer high-ambiguity candidates |
| **Second-chance repair** | Soft-deleted patterns re-evaluated each cycle |
| **I-Sub lexical similarity** | Greedy longest-common-substring — better than Jaccard for ontology terms |
| **Interval Labelling Schema** | O(1) subsumption over pattern hierarchy via preorder/postorder |
| **Backend performance analysis** | 1,200+ experiments tracked per backend/model → keep-rate statistics |
| **Pre-flight prediction** | Anti-pattern detection (3+ consecutive failures), target saturation (≥10), prediction threshold (0.15) |
| **Ontology vs LLM decider** | Formal decision framework: data-availability × complexity → ontology or LLM |
| **Category-based routing** | Targets classified as :programming, :tool-calls, :agentic, :natural-language → backend override |
| **Semantic clustering** | git-embed similarity ≥0.75 groups related targets; winning strategies propagate across clusters |
| **Strategy inheritance** | Similar targets auto-queue with inherited strategy from kept experiments (π Synthesis) |
| **Category strike tracking** | 3 consecutive failures freeze a category; reset on next kept result (∀ Vigilance) |
| **VSM health diagnostics** | Eight Keys scored per subsystem (AutoGo, AutoTTS, self-evolve) from kept hypotheses |

37 patterns ported from Semantica, AutoGo, LogMap, and VSM. The system audits itself using its own ontologies.

---

## The Competitive Layer

AutoGo-inspired **champion league** gates every new strategy — incumbents must be defeated in a category-specific gauntlet before being adopted. Champions compete within their domain (:programming, :natural-language, :agentic, :tool-calls), not globally. **Playout Cap Randomization** (80% quick / 15% medium / 5% deep) prevents over-specialization. Every cycle emits a machine-parseable `===RESULT===` JSON block for the **autoresearch loop**: commit → run → parse → keep/revert — now wired into AutoTTS trace outcome hooks.

**Head-to-head comparison** (promptfoo-style): every backend/model pair compared on shared targets (≥3 samples each) with 5% tie margin. Generates `mementum/knowledge/backend-comparison.md` and `model-comparison.md`. **Allium v2** adds trend tracking, regression detection, experiment prompt injection, and auto-repair mode.

**∀ Vigilance** (S3 Earth): Categories with 3 consecutive champion failures are frozen during gating, preventing wasted experiments on broken domains. Strikes reset when a category produces a kept result.

**π Synthesis** (S2 Metal): After a kept experiment, semantic clustering finds similar files (via git-embed) and auto-queues them with the winning strategy inherited — knowledge propagates across related targets without redundant exploration.

**Holdout evaluation** tracks real progress on a frozen set of targets — if train metrics improve but holdout doesn't, the system detects overfitting.

---

## The Operational Layer

Every hypothesis is classified by its **operation type** — this is the verbum (φ) layer:

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

## What It Absorbs (and How You Direct It)

### Research on Demand

```bash
./scripts/run-pipeline.sh
```

Researches 17+ repos via `gh api`, distills techniques, produces Allium v3 behavioral specs, feeds them into the analyzer. No batch prefetch — fetches only what fills gaps in the ontology.

The researcher is **benchmark-driven and self-evolving**:

| Strategy | When Used |
|----------|-----------|
| **own-repos-first** | Local codebase patterns before external sources |
| **deep-external** | Exhaustive external repo analysis |
| **topic-specific** | Targeted research on ontology-identified gaps |
| **quick-own-only** | Fast cycle when external API quota is low |

**Research quality pipeline:**
1. **Strategy benchmark** — All 4 strategies compete; best strategy wins per cycle
2. **Allium coherence check** — Findings validated for contradictions before use
3. **LLM noise stripping** — Conversational artifacts removed from raw findings
4. **Eight Keys scoring** — Research scored on ε Purpose (actionability), not just volume
5. **Ontology enrichment** — New techniques auto-extracted and merged into experiment ontology
6. **Outcome feedback** — Kept/discarded experiments adjust research priorities per source

The researcher reads knowledge gaps from the ontology, formulates questions, fetches specific files on demand, and enriches the ontology with each discovery.

### Structure Customer Data

```elisp
(let ((onto (gptel-auto-workflow--generate-experiment-ontology)))
  (message "Found %d classes, %d instances"
           (plist-get onto :class-count)
           (plist-get onto :instance-count)))
```

Auto-detected entity types, inferred relationships, XSD-typed properties. Add business rules:

```elisp
(setq gptel-auto-workflow--experiment-policy
      '(:required-fields ("id" "timestamp" "source")
        :forbidden-values ("null" "undefined")))
```

### Trace What Happened

```bash
cat var/tmp/experiments/*/results.tsv | grep "<target-file>"
```

Every experiment: hypothesis → change → outcome → decision. Causal chains. Impact classification. The history is structured, not buried in `git log`.

### Report to Stakeholders

```bash
ls mementum/knowledge/research-insights-*.md
ls mementum/knowledge/*-comparison.md
```

Knowledge pages per strategy: what worked, what didn't, Allium coherence checks, meta-learning recommendations. Backend and model comparison reports for data-driven provider selection. Send the markdown.

---

## Safety

| Guard | Prevents |
|-------|---------|
| Git worktree isolation | `main` never touched directly |
| 1844 tests + 1800s timeout | Broken code caught before staging |
| Ontology-aware provider routing | Reorders 5-provider fallback chain by historical keep-rate per target category |
| Force-push protection | Stashes dirty artifacts, merges origin/main, then pushes; never force-pushes |
| Server socket self-healing | 30s timer recreates lost daemon socket; no SIGKILL restart needed |
| Conflict marker detection | No `<<<<<<<` in committed code |
| 90-minute watchdog | No technique runs indefinitely |
| Policy engine | Forbidden paths sealed |

---

## Begin

```bash
git clone --recurse-submodules https://github.com/davidwuchn/minimal-emacs.d ~/.emacs.d
cd ~/.emacs.d && ./scripts/setup-packages.sh
./scripts/setup-eca-links.sh
# API keys in ~/.authinfo
./scripts/run-pipeline.sh
```

First run initializes itself. After that, it absorbs and improves on its own.

```elisp
(gptel-auto-workflow-run-async)        ; Channel energy now
(gptel-auto-workflow-status)           ; Check cultivation
```

---

Built on [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d). Extended with gptel, nucleus statecharts, mementum memory, verbum operational taxonomy, Semantica ontology, AutoGo competitive gating, LogMap inverted indexing and repair, Allium behavioral compilers. 37 patterns across 4 frameworks. The art grows with its practitioner.
