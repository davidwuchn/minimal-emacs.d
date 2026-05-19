# minimal-emacs.d + gptel-nucleus

> **An autonomous pipeline that researches, codes, verifies, and self-evolves — built on formal reasoning.**

A fork of [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d). Built on [gptel](https://github.com/karthink/gptel). Runs 3-6 improvement cycles per day inside Emacs.

---

## The Principle

```
λ engage(emacs).
  research(external) → compile(strategy) → execute(experiment) → verify(outcome) → learn(pattern)
  | ∀change: isolated(worktree) ∧ verified(tests) ∧ reviewed(AI)
  | self_referential: the system audits itself using its own ontologies
```

This is not a code generator. It is a **self-improving formal system** — it researches techniques from external sources, structures them into behavioral specifications, executes them as experiments in isolated environments, and feeds outcomes back into its own evolution.

Like the Northern Divine Art (北冥神功), it absorbs techniques from everywhere and converts them into its own capability. What worked in one codebase flows into the next. What failed becomes a guard rail. The art grows with its practitioner.

---

## The Architecture

Every cycle runs through four compilers — each examining the system's own behavior. This is the nucleus (ν) layer:

| Compiler | Input → Output | Answers |
|----------|---------------|---------|
| **Nucleus EDN** | Strategy prompt → statechart | "Is this instruction well-formed?" |
| **Nucleus Lambda** | Hypothesis → λ expression | "What principle does this encode?" |
| **Allium v3** | Research findings → behavioral spec | "Are these internally coherent?" |
| **OWL/SHACL** | Ontology dict → Turtle/SHACL | "What is the formal shape of what we've learned?" |

Results feed back into the next cycle's analyzer and strategy evolver. The compiler output is not a log — it is **input to the next iteration**.

---

## The Loop

```
Research (3min)  →  Evolution (2min)  →  Auto-Workflow (1-4h)  →  Post-Evolve (2min)
     ↓                                              ↓
  External findings                      Select target → Generate hypothesis
  + on-demand repo fetch                  → Implement fix → Run 89 tests
                                          → AI grade → AI review
                                          → Merge or learn
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

30 patterns ported from Semantica, AutoGo, and LogMap. The system audits itself using its own ontologies.

---

## The Competitive Layer

AutoGo-inspired **champion league** gates every new strategy — incumbents must be defeated in a gauntlet before being adopted. **Playout Cap Randomization** (80% quick / 15% medium / 5% deep) prevents over-specialization. Every cycle emits a machine-parseable `===RESULT===` JSON block for the **autoresearch loop**: commit → run → parse → keep/revert — now wired into AutoTTS trace outcome hooks.

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

Researches 17+ repos via `gh api`, distills techniques, produces Allium v3 behavioral specs, feeds them into the analyzer. No batch prefetch — fetches only what fills gaps in the ontology. The researcher is itself **ontology-aware and self-evolving**: it reads knowledge gaps, formulates research questions, fetches specific files on demand, and enriches the ontology with each discovery. Outcome feedback (kept/discarded) adjusts research priorities per source.

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
```

Knowledge pages per strategy: what worked, what didn't, Allium coherence checks, meta-learning recommendations. Send the markdown.

---

## Safety

| Guard | Prevents |
|-------|---------|
| Git worktree isolation | `main` never touched directly |
| 89 tests + 1800s timeout | Broken code caught before staging |
| 5-provider auto-failover | Rate limits detected, next backend activated |
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

Built on [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d). Extended with gptel, nucleus statecharts, mementum memory, verbum operational taxonomy, Semantica ontology, AutoGo competitive gating, LogMap inverted indexing and repair, Allium behavioral compilers. 30 patterns across 4 frameworks. The art grows with its practitioner.
