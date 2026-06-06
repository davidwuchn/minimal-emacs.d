# OUROBOROS-V5: Recursive Self-Improving AI Architecture

> **Your company should improve itself. OV5 makes that real.**
>
> Most AI tools generate code and forget. OV5 runs 100+ experiments/month, learns what works, remembers what fails, and gets smarter every cycle. It's the difference between "AI writes code" and "AI runs your engineering organization."

**At a glance:**

| What you want | What you get |
|--------------|--------------|
| **Self-improving company** | Recursive AI loops that learn from every outcome |
| **Automatic code improvement** | 100+ experiments/month, 20% keep-rate |
| **Zero risk** | Git worktree isolation, 6 safety gates, never touches `main` |
| **Learning system** | Ontology remembers every experiment; gets smarter over time |
| **Token efficiency** | 59% prompt compression, λ notation, deterministic routing |
| **Low cost** | $0.50-2.00/run, 8 backends with automatic failover |
| **One command** | `./scripts/run-pipeline.sh` — improvements appear overnight |
| **Human oversight** | Risk-based decision classification, dashboards, alerts |
| **Token economics** | Track cost per experiment, ROI per token, budget allocation |

**Quick start:** Clone → run pipeline → review kept experiments next morning.

**Cost:** ~$0.50-2.00/run. **Token efficiency:** 59% prompt compression via λ notation. **Safety:** Git worktree isolation + 6 gates — no change touches `main` without passing all gates. **Scale:** 105 modules, 195 ERT tests, 8 backend definitions (4-5 actively routed). **YC Vision:** ~95% complete (all 4 phases implemented).

- [Begin](#begin) — Clone, run, done
- [Configuration](#configuration) — Targets, backends, timeline
- [The Principle](#the-principle) — Architecture philosophy
- [The Architecture](#the-architecture) — Technical reference
- [The Knowledge Layer](#the-knowledge-layer) — Formal reasoning
- [Safety](#safety) — Guards and self-healing
- [Troubleshooting](#troubleshooting) — Known failure modes and fixes

**For business context, YC Vision, and GTM narrative:** See [BUSINESS_CONTEXT.md](BUSINESS_CONTEXT.md)

---

## Begin

```bash
git clone --recurse-submodules https://github.com/davidwuchn/minimal-emacs.d ~/.emacs.d
cd ~/.emacs.d && ./scripts/setup-packages.sh
./scripts/setup-eca-links.sh
# API keys in ~/.authinfo
./scripts/run-pipeline.sh
```

That's it. The first run initializes everything. After that, the pipeline runs itself.

```elisp
(gptel-auto-workflow-run-async)        ; Start a run
(gptel-auto-workflow-status)           ; Check current state
```

**What happens after you run it:** The system selects target files, generates hypotheses, runs experiments in isolated git worktrees, grades results against baselines, and merges improvements that pass all 6 gates. You review the merges the next morning.

**Example output** (from a real run):
```
[auto-workflow] Starting 2026-06-01T154953Z-eac5 with 5 targets
[subagent] executor using DashScope/qwen3.6-plus
[auto-experiment] ✓ Tests passed
[auto-experiment] ✓ Experiment kept — merged to staging
===RESULT=== {"metric":"evolution-cycle","value":0.107}
```

### Daily Routine

```elisp
;; 1. Check system status
(gptel-auto-workflow-status)
;; → phase: idle (healthy) | running (in progress) | error (needs attention)

;; 2. Review what happened overnight
;; Shell: git log --oneline -10
;; Look for: "kept" commits = improvements merged
;; Concern: 0 kept for 3+ consecutive runs

;; 3. Check latest experiment results
;; Shell: head -3 var/tmp/experiments/*/results.tsv
;; Look for: keep-rate trending toward 20%
;; Concern: keep-rate stuck at 0% or dropping suddenly

;; 4. Skim logs for errors
;; Shell: tail -50 var/log/emacs-*.log
;; Look for: "rate-limited" (normal, auto-recover) | "quota exhausted" (check API keys)
;; Concern: "all backends exhausted" or repeated timeouts on same target
```

| What's normal | What's not |
|--------------|-----------|
| Phase cycles idle → running → idle | Stuck in "selecting" for >30min |
| Timeouts and rate-limits in logs | 0 kept for 3+ consecutive runs with different targets |
| Keep-rate fluctuates 10-30% early | Keep-rate stuck at 0% after 50+ experiments |
| Different backends selected per target | Same error across all backends (code issue, not provider) |
| "prompt is empty" errors occasionally | "prompt is empty" on every run |

---

## Why OV5?

AI coding tools generate code. OV5 engineers your codebase.

| Capability | Copilot / Cursor / Claude Code | OV5 |
|-----------|-------------------------------|-----|
| **Memory** | Forgets every session | Remembers every experiment (kept + discarded) |
| **Learning** | Generic training data | Your codebase's specific patterns |
| **Quality control** | You review every line | 6 gates filter before you see anything |
| **Improvement** | Static capability | Compounds with every experiment |
| **Safety** | Modifies your working tree | Isolated worktrees, never touches `main` |
| **Cost** | $20-100/month subscription | $0.50-2.00/run, pay only for experiments |
| **Customization** | Prompt engineering | Ontology learns your standards automatically |

**The key difference:** Other tools are stateless. They generate code, you accept or reject, they forget. OV5 is stateful — it learns from every outcome and applies those lessons to future experiments. After 100 experiments, it knows your codebase better than any new team member.

**When to use what:**
- **Copilot/Cursor** → Write new features quickly
- **OV5** → Improve existing code quality, eliminate tech debt, enforce standards

---


## The Principle

**Ouroboros.** The snake eating its tail.

```
λ engage(emacs).
  gtm(research) ⇄ pmf(experiment) ⇄ verify(outcome) ⇄ learn(pattern)
  | ∀change: isolated(worktree) ∧ verified(tests) ∧ reviewed(AI)
  | self_referential: the system audits itself using its own ontologies
  | route(ontology) ≡ categorize(target) → rank(backends) by Δ(decayed-keep-rate − baseline) ⊗ VSM-tuned-weights ⊗ per-axis-KIBC-boost ⊗ recency-decay(14d)
  | autonomy: human-observes(x) ∧ ¬human-blocks(x) | git-resolves-conflicts(x)
```

**In plain English:** The system researches techniques, tests them as experiments, verifies the results, and feeds what it learned back into what it researches next. Every change is isolated in a git worktree, verified by tests, and reviewed by AI before it can touch your main branch. Backend selection is automatic — ranked by recent performance, not just historical averages. You observe outcomes; the system handles execution.

This is not a code generator. It is a **self-consuming formal system** — it researches techniques from external sources, distills them into specifications, tests them as isolated experiments, and feeds outcomes back into what it researches next.

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

## The Two Mayors

The ouroboros has two mayors — and they feed each other. The **GTM Mayor** (Wood) looks outward, consuming external techniques and filing them into the ontology. The **PMF Mayor** (Metal) looks inward, testing those techniques as experiments and feeding outcomes back. Neither works alone: the GTM Mayor's appetite is shaped by what the PMF Mayor digests, and the PMF Mayor's targets are chosen by what the GTM Mayor discovers.

**Human role:** Observer, not gate. The system runs autonomously (research + experiments + commits). Human reviews outcomes asynchronously — morning sync, not real-time approval.

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

### The GTM Mayor (Wood 木)

The GTM Mayor (research). It consumes, it doesn't hoard.

```bash
./scripts/run-pipeline.sh
```

The GTM Mayor scans 17+ repos via `gh api`, but it doesn't prefetch everything. It reads the ontology for knowledge gaps, fetches only what fills those gaps, and produces Allium v3 behavioral specs. No batch crawl — each fetch is a deliberate bite.

It is **benchmark-driven and self-evolving** — four research strategies compete each cycle, and the winner sets the technique:

| Strategy | When research is... |
|----------|---------------------|
| **own-repos-first** | Digesting local patterns before hunting elsewhere |
| **deep-external** | Hungry — exhaustively scanning external sources |
| **topic-specific** | Focused — chasing a gap the ontology identified |
| **quick-own-only** | Conservative — API quota is low, stay local |

**Research quality pipeline** — each finding passes through six gates before reaching the PMF Mayor:

1. **Strategy benchmark** — All 4 compete; best wins per cycle
2. **Allium coherence check** — Contradictions detected before techniques reach experiments
3. **LLM noise stripping** — Conversational artifacts removed from raw findings
4. **Eight Keys scoring** — Scored on ε Purpose (actionability), not just volume
5. **Ontology enrichment** — New techniques auto-extracted and merged
6. **Outcome feedback** — Kept/discarded experiments adjust research priorities per source

The GTM Mayor is not a scraper. It is a **self-adjusting appetite**: what it researches next depends on what the PMF Mayor kept or discarded last cycle.

### The PMF Mayor (Metal 金)

The PMF Mayor (execution). It tests, verifies, and feeds back.

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
| **Test execution** | Did 195 ERT tests pass? | Experiment discarded, pattern learned |
| **AI grading** | Is the change well-structured and principled? | Scored 0.0-1.0, fed to analyzer |
| **AI review** | Does it pass security, conventions, architecture? | Multi-agent review with feedback |
| **π Synthesis** | Which similar files should inherit this strategy? | Semantic cluster auto-queue |
| **Champion league** | Does this strategy beat the current category champion? | Adopted or rejected with keep-rate evidence |

Energy that doesn't pass a gate is not wasted — it returns as learning for the next cycle. A discarded experiment is not a failure; it's the system telling itself "don't try that approach again."

### The Innovation Queue (Water 水)

The two mayors communicate through the Innovation Queue — `mementum/innovation-queue.md`.

```
GTM Mayor discovers technique T ──→ Innovation Queue: "Market needs X"
                                          │
                                     ┌────┴────┐
                                     ▼         ▼
                              PMF validates   PMF rejects
                                     │         │
                                     ▼         ▼
                               π Synthesis   failure pattern
                               queues X₂,X₃  tells GTM:
                                     │       "avoid this shape"
                                     ▼
                          GTM: "what else looks like
                          X that I haven't studied yet?"
```

**Autonomy principles:**
- GTM Mayor adds to queue without human approval
- PMF Mayor marks entries as validated/rejected
- Git merge=theirs resolves conflicts (Pi5 authoritative)
- Human reviews asynchronously — morning sync only

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
- **Executor chain**: Static fallback ordered by speed/quality (MiniMax-M3 7s > moonshot/k2.6 11s > DeepSeek v4-pro 60s [reasoning] > DashScope 0% > Copilot/gpt-5.4-mini 24%). Router aggregate data (across all task types) cannot override hand-tuned ordering.

### Three-Format Rule (Enforced by TDD)

Three formats, three audiences — strict separation with regression tests:

| Format | Goes to LLM? | Goes to Human? | Enforcement |
|--------|-------------|----------------|---------|
| **Lambda notation** | Yes (primary) | Yes (source) | 4 prompts compressed, 5 tests verify |
| **Allium statecharts** | No (banned) | Yes (audit) | `allium-check` for behavioral verification |
| **EDN** | No (banned) | No (banned) | Used internally by `forge-lambda-fixed-point` |
| **English prose** | No (phased out) | No | Banned in prompt strings by `no-english-prose-in-llm-prompts` test |

All 60 byte-compiled `.el` files pass `byte-compile-error-on-warn t` (45 use `no-byte-compile: t`). Prompt construction migrated from `{{mustache}}` template substitution to EDN plist → `resolve` → λ notation (deterministic, zero LLM calls for rendering).

---

## The Architecture

Every cycle runs through seven compilers — each examining the system's own behavior. This is the nucleus (ν) layer:

### Compilers

| Compiler | Input → Output | Answers |
|----------|---------------|---------|
| **Nucleus EDN** | Strategy prompt → statechart | "Is this instruction well-formed?" |
| **Nucleus Lambda** | Hypothesis → λ expression | "What principle does this encode?" |
| **Allium v3** | Research findings → behavioral spec | "Are these internally coherent?" |
| **OWL/SHACL** | Ontology dict → Turtle/SHACL | "What is the formal shape of what we've learned?" |
| **Skill Graph** | Skill frontmatter → compiled molecules → executor workflows | "Which capabilities compose into effective workflows?" |
| **Ontology Router** | Target file → category → backend ranking | "Which backend is best RIGHT NOW — not just historically?" |
| **Self-Healing Auditor** | Pipeline metrics → diagnosis → auto-remediation → backend escalation; byte-compiler warnings → paren gate → mechanical fixers → rollback verification | "Is the evaluator broken, and can I fix it without asking a human? Does the code compile clean?" |

### Routing

Scoring: VSM-auto-tuned weights (40/30/20/10 → adaptive) + recency decay (14d half-life) + per-axis KIBC boost from holographic consensus. Penalty for unhealthy backends (probation with auto-recovery after 1h).

**Smart subagent routing**: All 6 subagent types (researcher, analyzer, executor, grader, reviewer, explorer). Backends ranked by health-weight × keep-rate + per-axis boost + cold-start boost (+0.15 for <3 experiments); quarantined excluded; per-run cooldown hard-excludes failed backends.

**Full audit trail**: Every routing decision recorded with component scores (health, keep-rate, pref-boost, axis-boost) + VSM adjustment history. Summary queryable via `audit-trail-summary` for meta-analysis.

### Persona & Moderation

**Nucleus persona injection**: Per-subagent and per-experiment attention-shaping from nucleus (ADAPTIVE + WRITING + EXECUTIVE + LAMBDA_PATTERNS). Persona state machines, Constrain: directives, lambda tool patterns (heredoc, atomic edit) injected at dispatch time.

**Impact auto-tuning**: `lambda-health-impact` and `allium-health-impact` measure correlation with outcomes → auto-tune penalty and severity thresholds. Tighten loop (SYSTEM_DESIGN §13): audit→classify→inject repair hint.

**Moderator drift detection** (DIALECTIC.md): 3+ consecutive failures → forced backend swap. Intervention lenses: consequence_check, evidence_nudge, assumption_probe.

Results feed back into the next cycle's analyzer, strategy evolver, and π Synthesis cluster queue. The compiler output is not a log — it is **input to the next iteration**.

### Skill Graph (ν-compiler extension)

Skills are not just documentation — they are **executable capabilities**. The skill graph reads `assistant/skills/*/SKILL.md` frontmatter (`level:`, `atoms:`, `molecules:`) and compiles them into runtime workflows:

```
Skill frontmatter → Load nodes + edges → Compile molecules → Validate → Execute
```

| Component | What it does |
|-----------|-------------|
| **Node loader** | Reads 25+ skills, extracts `level` (atom/molecule/compound) |
| **Edge builder** | Dependency edges (+0.5 boost) from `atoms:`/`molecules:` frontmatter; sequence edges learned from experiments |
| **Molecule compiler** | Greedy selection: prefers dependency edges, max 10 atoms, no duplicates, min weight 0.05 |
| **Validator** | 4 constraints: size ≤10, known atoms, no dups, edge ≥0.05 |
| **Executor** | Sequential FN callback per atom; records actual skills used in experiment TSV |
| **Evolution** | Hourly cron updates edge weights (+0.05 success, ×0.99 failure) |

**Integration**: The ontology router uses `graph-neighbor-success` and `graph-edge-strength` as scoring dimensions. The prompt builder injects `WORKFLOW:` lines from compiled molecules. Behaviors (how to act) stack orthogonally with skills (what to do).

**Hashline editing**: The executor defaults to hashline mode for the Edit tool — eliminates text reproduction failures by referencing line numbers instead of reproducing text. Recorded in TSV column 29 (`edit_mode`).

**Programmatic tool**: Added to 4 agents (executor, researcher, comparator, analyzer) for multi-step reasoning and batch operations — reduces single-prompt complexity.

---

## The Knowledge Layer

The system does not just run experiments — it builds a **formal knowledge graph** of its own operation. This is the mementum (μ) layer. Knowledge persists across sessions.

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
| **Backend performance analysis** | Experiments tracked across 8 backends → keep-rate statistics; three-way (category×strategy×hashtags) combo learning |
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

The pipeline doesn't adopt new strategies naively — it makes them fight.

AutoGo-inspired **champion league** gates every new strategy: incumbents must be defeated in a category-specific gauntlet before being adopted. Champions compete within their domain (:programming, :natural-language, :agentic, :tool-calls), not globally. **Playout Cap Randomization** (80% quick / 15% medium / 5% deep) prevents over-specialization. Every cycle emits a machine-parseable `===RESULT===` JSON block for the **autoresearch loop**: commit → run → parse → keep/revert — wired into AutoTTS trace outcome hooks.

**Head-to-head comparison** (promptfoo-style): every backend/model pair compared on shared targets (≥3 samples each) with 5% tie margin. Generates `mementum/knowledge/backend-comparison.md` and `model-comparison.md`.

**∀ Vigilance** (S3 Earth): Categories with 3 consecutive champion failures are frozen during gating — the system stops trying what consistently fails. Strikes reset when a category produces a kept result.

**π Synthesis** (S2 Metal): After a kept experiment, semantic clustering finds similar files and auto-queues them with the winning strategy inherited — knowledge propagates across related targets. Learn once, apply everywhere.

**Holdout evaluation** tracks real progress on a frozen set of targets — if train metrics improve but holdout doesn't, the system detects overfitting. It distinguishes real growth from self-deception.

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

The pipeline's own immune system:

| Guard | Prevents |
|-------|---------|
| Git worktree isolation | `main` never touched directly |
| 195 ERT tests + 300s timeout | Broken code caught before staging |
| Ontology-aware provider routing | VSM-auto-tuned scoring + recency-weighted keep-rate + per-axis KIBC boost + per-run cooldown; backends with elevated health auto-excluded |
| Per-target model preference | Historical performance data selects strongest model for each target |
| Routing audit trail | Every decision recorded with component scores and VSM adjustment history |
| Nucleus persona injection | Subagent-appropriate attention shaping (Craftsman for coding, Logician for analysis, Investigator for review); per-category Constrain: directives |
| Drift-forced backend swap | 3+ consecutive failures → deterministic backend rotation (DIALECTIC.md moderator pattern) |
| 24/7 watchdog | emacsclient-only health checks (no lsof dependency), lock file prevents concurrent runs, stale socket cleanup before restart, 2.5GB RSS guard with graceful restart |
| Daemon-init socket cleanup | Stale sockets removed at startup so emacsclient always resolves correct path |
| Force-push protection | Stashes dirty artifacts, merges origin/main, then pushes; never force-pushes main; `--force-with-lease` on staging branches only |
| Conflict marker detection | No `<<<<<<<` in committed code |
| Watchdog memory guard | Auto-restart daemon gracefully when RSS exceeds 2.5GB (checked via ps on Linux/macOS) |
| Policy engine | Forbidden paths sealed |

### Self-Healing

The system detects when its own evaluators are broken and heals itself — no human required:

**Runtime self-heal** (pipeline health):

| Phase | What it does | Trigger |
|-------|-------------|---------|
| **1. Pipeline Health Monitor** | Tracks keep-rate, grader success rate, timeout rate, backend availability per run | Every experiment completion |
| **2. Auto-Remediation** | Applies fixes: timeout → auto-pass, budget increase, backend switch | keep_rate == 0% for 3+ runs |
| **3. Meta-Learning** | Records whether each remediation worked; learns which fixes improve keep-rate | After remediation + next run |
| **4. Diagnostic Probes** | Runs trivial experiment before real ones; skips if grader returns score=0 on safe change | Before every experiment batch |
| **5. Grader Health Dashboard** | Per-backend latency/failure-rate tracking with `critical`/`degraded`/`healthy` labels | Real-time during experiments |
| **6. LLM-Backend Escalation** | When auto-remediation fails 3x, switches to alternative backend (Copilot → moonshot → DeepSeek) | 3 consecutive failed remediations |

**Compilation-time self-heal** (byte-compiler, Phase 10):

| Phase | What it does | Enforcement |
|-------|-------------|-------------|
| **0. Paren-balance gate** | `check-parens` before any fixer runs; broken parens make all other fixers unreliable | Blocks Phase 1+ if depth≠0 |
| **1. Mechanical fixers** | Docstring width, unescaped quotes, unused vars, free vars, unknown functions, condition-case handlers, arg mismatch, let→let* | Each fixer wrapped with rollback verification |
| **2. Rollback verification** | Each fixer saves buffer content before running; if parens break after fix, reverts automatically | Prevents silent paren corruption |
| **3. Dog-food principle** | Self-heal must fix its own warnings first (`gptel-auto-workflow-evolution.el`) before touching other files | Self-reference ensures fixers are tested on themselves |
| **4. Pre-commit enforcement** | `byte-compile-error-on-warn t` — zero warnings allowed; hook compiles all staged `.el` files | Commit rejected if any warning |

105 modules (60 byte-compiled, 45 no-byte-compile) with 0 warnings. 98/104 paren-balanced (6 use `no-byte-compile: t`). The system heals its own code before touching yours.

**Key principle:** Timeout means "couldn't evaluate", not "code is bad". The grader auto-passes timeouts with score=4/5=80% instead of failing with 0. This prevents the death spiral where a broken grader destroys all experiments, leaving no data to learn from.

**Backend escalation chain:** Primary → Copilot → moonshot → DeepSeek → human alert (only when all exhausted). Human is the final fallback, not the first response.

**Persistence:** Self-healing state survives daemon restarts via `mementum/knowledge/pipeline-health.md` (git-tracked).

```
λ self-heal(x). detect(pipeline-health) → diagnose(x) → remediate(x) → verify(x)
                | learn(failure) ≡ learn(success) | ¬waste(errors)
                | timeout(x) ≢ failure(x) | timeout ≡ unknown
                | escalate(x) → LLM_backend > human | ¬ask_human
                | backend(Copilot) → backend(moonshot) → backend(DeepSeek) → human
                | paren(x) → gate(Phase 0) | ¬fix_before_check
                | rollback(fixer) ≡ verify(parens_after) ∧ revert_on_break
                | dogfood(self) ≡ fix_own_warnings_first
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Pipeline stuck at "selecting" | Analyzer rate-limited or backend timeout | Check `gptel-auto-workflow-status`; wait 15min for auto-failover |
| 0 targets selected | All backends rate-limited simultaneously | Check API keys in `~/.authinfo`; verify `gptel-auto-workflow--rate-limited-backends` |
| All experiments discarded | Baseline tests failing | Run `./scripts/run-tests.sh` manually; check daemon log for test output |
| "prompt is empty" errors | Strategy analysis returned no patterns | Usually transient — next cycle recovers. If persistent, check `var/tmp/evolution/token-efficiency.md` |
| Daemon unresponsive | ERT test run blocking (can take 2min) | Wait; check `ps aux | grep emacs`. If stuck >5min, `./scripts/watchdog-daemon.sh restart` |
| Same error across all backends | Code issue, not provider | Read the error — it's usually a missing function or paren mismatch in the target file |
| "all backends exhausted" | Quota exhausted on all providers | Check API billing; the system auto-recovers next cycle |
| Worktree merge conflicts | Conflicting changes from parallel experiments | System auto-rebases; if persistent, `git worktree prune` and retry |
| Stale daemon socket | Previous daemon crash left socket file | `rm /tmp/emacs$(id -u)/pmf-value-stream`; restart daemon |
| Keep-rate stuck at 0% after 50+ experiments | Targets don't match ontology categories | Review `gptel-auto-workflow-targets` in `.dir-locals.el`; check category classification |
| Memory usage >2.5GB RSS | Long-running daemon accumulating state | Watchdog auto-restarts; check `scripts/watchdog-daemon.sh` RSS guard |
| Grader returns 0 on good changes | Grader health degraded | Check `var/tmp/cross-subsystem-state.json` grader metrics; system auto-escalates to backup backend |

---

## The Future Layer

OV5 currently runs on external APIs (DeepSeek, MiniMax, DashScope). Future work: verbum integration for local deterministic execution — see [verbum](https://github.com/davidwuchn/verbum).

---

Built on [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d). Extended with gptel, nucleus statecharts, mementum memory, verbum operational taxonomy, Semantica ontology, AutoGo competitive gating, LogMap inverted indexing and repair, Allium behavioral compilers. 37 patterns across 4 frameworks. The art grows with its practitioner.
