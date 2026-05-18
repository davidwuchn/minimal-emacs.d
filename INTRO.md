# minimal-emacs.d + gptel-nucleus

> **Your AI teammate that researches, codes, reviews, and learns — so you ship faster.**

A fork of [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d) turned into an autonomous AI agent system. Built on [gptel](https://github.com/karthink/gptel). Runs 3-6 autonomous improvement cycles per day inside Emacs.

---

## If You're a Forward Deployed Engineer

Your job: ship fixes fast, know what changed, never break prod. Here's how this helps:

**You find a bug or a pattern that needs fixing across dozens of files.** Instead of spending hours on grep → edit → test → repeat, you tell the pipeline what to optimize. It researches similar fixes, proposes changes, tests them in isolation, and either merges or explains why it failed. You review the diff.

**You're integrating with a customer's codebase and need to understand its patterns.** The system has already built an ontology of your code — it knows which strategies work on which files, which operations tend to succeed, and where contradictions hide. You query the knowledge pages instead of grepping blind.

**You need an audit trail of what changed and why.** Every experiment is recorded with hypothesis, delta, decision, and causal links to prior experiments. You can trace "why was this function refactored in March?" back to the specific research that triggered it.

**You have mass customer data and need to structure, validate, and reason over it.** The same ontology pipeline that governs 89 code files can auto-generate OWL ontologies from your data, validate records against business rules, detect conflicting values from different sources, and diff what changed between data loads. You feed it raw data, it returns structure.

---

## What It Does (In Practice)

```
You: "My project has nil-safety bugs. Fix them."
Pipeline: researches 18 repos for nil-guard patterns,
          generates 10+ hypotheses, tests them,
          merges the ones that pass 89-test suite,
          learns which strategies actually worked,
          gets better next cycle.
```

| You Give It | You Get Back |
|-------------|-------------|
| A target file pattern | Tested, reviewed code changes (merged or explained) |
| A research question | Relevant techniques from GitHub, arXiv, and 18+ repos |
| Raw data (JSON, CSV, logs) | Auto-generated ontology (classes, properties, types) |
| Nothing (it runs autonomously) | 3-6 cycles/day of self-directed improvement |
| A status check | What changed, what failed, what it learned |

---

## Quick Start

```bash
# 1. Clone
git clone --recurse-submodules https://github.com/davidwuchn/minimal-emacs.d ~/.emacs.d

# 2. Install packages
cd ~/.emacs.d && ./scripts/setup-packages.sh

# 3. Setup ECA symlinks
./scripts/setup-eca-links.sh

# 4. Configure API keys in ~/.authinfo
# machine api.minimaxi.com login apikey password YOUR_KEY
# machine api.kimi.com      login apikey password YOUR_KEY

# 5. Run it
./scripts/run-pipeline.sh
```

That's it. No manual intervention needed after setup.

---

## Three Things It Does For Your Job

### 1. Ships Fixes You'd Rather Not Write

Repetitive code fixes — nil guards, error handling, DRY refactors — are automated. Each experiment runs in a git worktree, passes through a 6-gate pipeline (analyzer → executor → grader → comparator → reviewer → staging), and either merges or tells you why not.

```bash
# Run a manual experiment on a specific file
emacsclient -e "(gptel-auto-workflow-run-async)"

# Check what happened
./scripts/run-auto-workflow-cron.sh status
```

**What you review**: a clean git diff with a change summary, before/after scores, and the grader's reasoning. You decide whether to merge to main.

### 2. Explains What Changed and Why

The system doesn't just make changes — it builds a **living knowledge graph** of your codebase. Every cycle, it auto-generates:

- **Knowledge pages** per strategy: which targets improved, which didn't, and the Allium behavioral spec checking for contradictions
- **Impact classification**: every experiment tagged as BREAKING, POTENTIALLY BREAKING, or SAFE
- **Causal chains**: which experiments caused which improvements, tracing root causes
- **Cross-cycle diffs**: what knowledge was added, removed, or changed since last cycle

```bash
# View the latest ontology of your pipeline's operation
cat var/tmp/evolution/experiment-ontology.ttl

# Browse knowledge pages (Markdown + Allium-annotated)
ls mementum/knowledge/research-insights-*.md
```

### 3. Learns From Every Run

**195+ experiments** have produced **40+ evolved strategies**. The system tracks which approaches work, which don't, and automatically adjusts:

- **KIBC-M 15-axis classification**: every hypothesis tagged by operation type (nil-safety, composition, pattern-matching, etc.) — you can see which categories produce the best results
- **Pareto frontier**: balances exploration (trying new things) vs exploitation (doing what works)
- **Policy engine**: enforces limits (max experiments per file, min keep-rate) so it doesn't waste API quota on hopeless targets

---

## FDE Superpower: Ontology For Your Data, Not Just Ours

Forward Deployed Engineers deal with **mass, messy data** — customer databases, log streams, API responses, config sprawl. The same ontology system that structures our pipeline can structure *yours*:

**You have 10,000 JSON records from a customer's API and need to understand what's in them.** Feed them to the ontology generator:

```elisp
;; Generate ontology from your data
(let ((onto (gptel-auto-workflow--generate-experiment-ontology)))
  (gptel-auto-experiment--owl-save
   onto "~/customer-data-ontology.ttl"
   (lambda (ok) (message "Saved OWL ontology"))))
```

Result: auto-detected classes (entity types), inferred properties (relationships between them), XSD-typed fields. No hand-authoring.

**You need to validate a dataset against business rules.** Add rules to the policy engine:

```elisp
(setq gptel-auto-workflow--experiment-policy
      '(:max-items-per-entity 100
        :min-confidence 0.7
        :required-fields ("id" "timestamp" "source")
        :forbidden-values ("null" "undefined" "N/A")))
```

Any record that violates these gets flagged. Same validation-result pattern — `(valid, errors, warnings)`.

**You have conflicting data from two sources.** The conflict detector spots opposing claims:

```
[conflict] 3 hypothesis opposition(s) detected:
  customer_records: 2 opposing pairs (high) — Multiple opposed outcomes
  user_profiles: 1 opposing pair (medium) — Contradictory results
```

**You need to explain to a customer what changed between data loads.** Cross-cycle diff:

```bash
cat var/tmp/evolution/knowledge-snapshot.el
# Shows: +3 new classes, -1 removed class, ~2 changed
```

The core insight: **you don't write ontology code.** You feed the system data and get back structure, validation, and reasoning. Same engine that audits our 89-file codebase can audit your 100,000-record dataset.

---

## Debugging: When You Need to Know What Happened

```bash
# Full pipeline status
./scripts/run-auto-workflow-cron.sh messages

# Per-experiment details
cat var/tmp/experiments/*/results.tsv | head -1  # header
cat var/tmp/experiments/*/results.tsv | grep kept

# Knowledge page quality scores
# Logged every cycle: coverage, completeness, relation links
# Look for messages like:
# [evaluator] Knowledge pages: 85% coverage, 92% completeness, 60% linked

# Policy violations (what the system refused to do)
# Look for: [policy] VIOLATION: Target 'foo.el' has 12 experiments (max 10)
```

---

## The Pipeline

```
Research (3min)  →  Evolution (2min)  →  Auto-Workflow (1-4h)  →  Post-Evolve (2min)
     ↓                                              ↓
  External findings                      worktree → analyzer
  + 18-repo prefetch                     → executor → grader
                                         → benchmark → decide
                                         → reviewer → staging
```

Each experiment: selects target → generates hypothesis → implements fix → runs tests → grades itself → gets reviewed → merges or feeds back into learning.

---

## Safety (Because You Deploy to Production)

| Guard | What It Prevents |
|-------|-----------------|
| Git worktree isolation | Never touches `main` directly |
| 89-test suite, 1800s timeout | Broken code caught before staging |
| Conflict marker detection | No `<<<<<<<` in committed code |
| 5-provider failover chain | Survives API rate limits |
| 90-minute watchdog | Kills stuck workflows |
| Quota awareness | Skips runs when API exhausted |
| Policy engine | Rejects forbidden targets (packages/, var/, tests/) |

---

## Requirements

- Emacs 29.1+ on macOS or Linux
- API keys for at least one of: MiniMax, moonshot, DashScope, DeepSeek, Cloudflare Gateway
- Git, `gh` CLI (for repo prefetch), `timeout` (for staging verification)

---

## Key Commands

```elisp
;; Manual triggers (inside Emacs)
(gptel-auto-workflow-run-async)        ; Start workflow
(gptel-auto-workflow-status)           ; Check status  
(gptel-auto-workflow-run-research)     ; Run researcher now
```

```bash
# From terminal
./scripts/run-pipeline.sh              # Full pipeline
./scripts/run-auto-workflow-cron.sh status    # Status
./scripts/run-auto-workflow-cron.sh messages  # Recent activity
```

---

## Directory Structure

```
~/.emacs.d/
├── lisp/modules/         80+ Elisp modules (agents, tools, evolution)
├── packages/              Git-tracked deps (gptel, nucleus, mementum)
├── assistant/             Agent prompts, skills, 40+ evolved strategies
├── tests/                 57 regression test files
├── scripts/               Pipeline orchestration, cron, setup
├── mementum/              AI memory: insights, patterns, knowledge pages
├── var/tmp/               Runtime: experiments, traces, findings, staging
│   └── evolution/         Auto-generated ontology, diffs, scores
├── var/elpa/              Package state
└── eca/                   Provider configuration
```

---

## Upstream

Built on [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d) by James Cherti. See `README.md` for the base Emacs configuration.

Key additions: AI module loading, gptel + nucleus + ECA integration, autonomous pipeline orchestration, Git-tracked packages (avoids ELPA lag), Semantica-inspired ontology and knowledge management system.
