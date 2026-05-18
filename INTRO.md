# minimal-emacs.d + gptel-nucleus

> **Absorb everything. Convert it to your own power. Grow stronger with every fight.**
>
> Like the Northern Divine Art from the martial world — this system researches external techniques, assimilates them into working code, and learns from every outcome. You don't write fixes. You channel them.

A fork of [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d). Built on [gptel](https://github.com/karthink/gptel).

---

## Bei Ming Shen Gong, For Your Codebase

In the classics, the Northern Divine Art (北冥神功) does one thing no other art can: it absorbs the internal energy of any opponent and makes it yours. You don't need to cultivate for decades. You just need to touch them, and their power flows into you.

This is the same principle, applied to software.

**Every technique your pipeline absorbs — from 18 repositories, from arXiv, from GitHub — becomes a working code change in your project. Every experiment that fails teaches you what not to do. Every experiment that succeeds feeds back into the strategy for the next one.**

You are not the one writing fixes at 2am. You are the one channeling an entire research pipeline through your fingertips.

---

## What You Absorb

### From the Outside World

The system reaches out and pulls techniques from everywhere:

```
17 sources → fetch on demand → distill → strategy → execute
via gh CLI  ↗    GitHub    ↗   arXiv    ↗
```

A single command starts the flow:

```bash
./scripts/run-pipeline.sh
```

The pipeline researches similar fixes across all sources, selects targets, generates hypotheses, implements changes, runs 89 tests, has an AI reviewer grade the work, and merges what passes. What was once scattered across the internet is now running in your codebase.

**What you see**: a clean git diff. Before/after scores. The grader's reasoning. You approve or redirect. The power was never yours to write — only to direct.

### From Customer Data

A customer drops 10,000 JSON records on you. "Make sense of this."

```elisp
(let ((onto (gptel-auto-workflow--generate-experiment-ontology)))
  (message "Found %d classes, %d instances"
           (plist-get onto :class-count)
           (plist-get onto :instance-count)))
```

The system absorbs the data — detects entity types, infers relationships, types every field — and returns a formal ontology. What was chaos is now structure. Add rules to filter out the impure:

```elisp
(setq gptel-auto-workflow--experiment-policy
      '(:required-fields ("id" "timestamp" "source")
        :forbidden-values ("null" "undefined")))
```

Violations are flagged. Only clean energy flows through.

### From the Past

Production is down at 2am. You need to know *why*.

```bash
cat var/tmp/experiments/*/results.tsv | grep "<target-file>"
```

Every experiment leaves a trace: hypothesis → change → outcome → decision. Causal chains link experiments together. Impact classification marks every change as BREAKING, POTENTIAL, or SAFE. The system has already absorbed its own history — you just read it.

### From Your Own Progress

The customer asks: "What did you do for us in the last two weeks?"

```bash
ls mementum/knowledge/research-insights-*.md
```

Each knowledge page is a chapter of your cultivation: strategies tried, targets improved, contradictions detected and resolved, meta-learning on what works. Send the markdown. The story tells itself.

---

## How the Absorption Works

Every change passes through six gates. Energy that can't pass a gate is not wasted — it returns as learning for the next cycle.

```
Select target → Generate hypothesis → Implement fix → Run tests → AI grade → AI review → Merge or learn
                                                                                          ↓
                                                                              Feeds back into
                                                                              strategy evolution
```

All operations in isolated git worktrees. `main` is never touched until you choose.

### The Inner Compass

As the system absorbs, it also *understands*. It builds a knowledge graph of its own operation:

| Capability | Principle |
|-----------|----------|
| **Ontology generation** | Chaos becomes form — raw data yields classes, properties, relationships |
| **Allium behavioral checking** | Internal contradictions are detected and flagged — no technique is practiced with hidden flaws |
| **Knowledge page scoring** | Every insight is measured: coverage, completeness, coherence |
| **Conflict detection** | Opposite approaches on the same target are exposed immediately |
| **Impact classification** | Every change labeled: safe, dangerous, or needing caution |
| **Causal chains** | You can trace any outcome back to its root |
| **Cross-cycle diff** | See what was gained and what was discarded between cycles |
| **Policy engine** | Rules prevent wasted energy — no technique practiced beyond its worth |
| **KIBC-M axis classification** | Every hypothesis is typed (:K :I :B :C :M ...) — 15 operation axes from the verbum framework |
| **Self-evolution loop** | What worked feeds back into strategies, skills, and research priorities — the art sharpens itself |

### Four Schools, One Art

Each cycle, four compilers examine the system's own practice — four masters checking your form:

| Compiler | Examines | Asks |
|----------|---------|------|
| Nucleus EDN | Your strategy prompts | "Is this instruction clear enough to follow?" |
| Nucleus Lambda | Your hypotheses | "What principle are you really encoding?" |
| Allium v3 | Your research findings | "Are these internally consistent, or do they contradict?" |
| OWL/SHACL | Your ontology | "What is the formal shape of what you've learned?" |

Results flow back into the next cycle. The form sharpens itself.

---

## Guarding the Meridians

Cultivation without discipline is self-destruction. These safeguards ensure you absorb without breaking:

| Guard | Protects Against |
|-------|-----------------|
| Git worktree isolation | `main` is never touched directly |
| 89 tests + 1800s timeout | Corrupted energy is caught and expelled |
| Conflict marker detection | No `<<<<<<<` in committed code |
| 5-provider auto-failover | If one channel closes, another opens — rate limits detected and bypassed |
| 90-minute watchdog | No technique runs forever |
| Quota awareness | No technique practiced beyond available resources |
| Policy engine | Forbidden paths are sealed |

---

## Begin Your Practice

```bash
git clone --recurse-submodules https://github.com/davidwuchn/minimal-emacs.d ~/.emacs.d
cd ~/.emacs.d && ./scripts/setup-packages.sh
./scripts/setup-eca-links.sh

# API keys in ~/.authinfo:
# machine api.minimaxi.com login apikey password YOUR_KEY

./scripts/run-pipeline.sh
```

First run initializes itself. After that, it absorbs and improves on its own.

### Commands

```elisp
;; Inside Emacs — direct the flow
(gptel-auto-workflow-run-async)        ; Channel energy now
(gptel-auto-workflow-status)           ; Check your cultivation
(gptel-auto-workflow-run-research)     ; Reach outward
```

```bash
# Terminal — observe from above
./scripts/run-pipeline.sh              ; Full absorption cycle
./scripts/run-auto-workflow-cron.sh messages  ; Recent activity
```

---

Built on [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d). Extended with gptel + nucleus + ECA, autonomous pipeline, Semantica ontology, Allium behavioral compilers. The art grows with its practitioner.
