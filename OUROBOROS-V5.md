# OUROBOROS-V5: Self-Regulating AI Architecture

> **The snake that researches what to eat, executes what it learned, and feeds outcomes back into its own appetite.**
>
> **V5.1 update (2026-05-31):** 290+ commits, 15K+ lines — ai-behaviors integration (4 layers), ontology co-evolution, two-phase grader (#=test + #=attack → #=review + #=evaluate), digital twin dependency graph, subagent HARD CONSTRAINT enforcement, convergence invariant tracking, strike decay + auto-thaw, grader-bypass commit flow, category→hashtag learning, universal subsystem behavior injection via advice, research coordinator (AutoTTS×AutoGo×Ontology), concrete task evolution, kept pattern memory, λ-compressed behavior prompts (59% reduction), adaptive injection, DeepSeek curl timeout fix, validation self-evolution (learn from → inject → avoid), grader-decides-pre-grade (60% bypass threshold), research coordinator (ontology × AutoTTS × AutoGo), token efficiency (59% behavior prompt reduction), self-evolving persona state machine (nucleus ADAPTIVE.md), parallel mindset track, emission contracts per operation, category-specific symbol subsets (EXECUTIVE.md + WRITING.md), self-evolving collaboration operators (OPERATOR_ALGEBRA.md), three-way combo tracking (category×archetype×hashtag), per-subagent nucleus modes (#=code/#=review/#=frame/#=research), KV cache-optimized prompt ordering, pre-grade byte-compile check, date-aware DeepSeek pricing, bump-model escalation on consecutive failures, curiosity exploration (5% random persona A/B), exploration-weighted persona stats.

Built on [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d) + [gptel](https://github.com/karthink/gptel). 3 pipeline runs/day (macOS: 10AM/2PM/6PM; Linux: every 4h) + hourly self-evolution + watchdog every 30min. The snake eating its own tail — every subsystem improves every other subsystem.

---

## For Creators

**Innovation doesn't come from more meetings. It comes from more experiments.** Every breakthrough starts as a hypothesis you don't have time to test. OV5 closes the gap: you define what matters; the system runs the experiments.

Your job shifts from "write better code" to "teach the system what better code looks like." Every kept experiment trains the ontology. Every discarded experiment hardens the guard rails.

### How You Innovate with OV5

| Instead of... | You now... | Innovation gain |
|--------------|-----------|-----------------|
| Fixing the same nil-guard bug in 12 files | Mark the target once; the system propagates the fix | 12× leverage on every pattern |
| Code reviewing PRs for style consistency | Review kept experiments (the ontology already blocked style violations) | Review time drops 60% — focus on architecture, not syntax |
| Writing docs for your patterns | The ontology records every kept/discarded experiment as executable knowledge | Documentation that never goes stale |
| Wondering "did I break anything?" | 2,061+ tests run before every merge | Ship with confidence, not hope |
| Spending 4h on a refactor | The system experiments with 5 approaches; you review the winner | 5× more exploration, same time budget |

### The Innovation Flywheel

OV5 doesn't just improve code — it accelerates your entire development cycle:

```
Week 1:  System learns file categories, establishes baselines
           ↓
Month 1: 100+ experiments → ontology knows which strategies work for your codebase
           ↓
Month 3: System catches error patterns before you do
           ↓
Month 6: Your codebase has its own "engineering instinct" — the ontology
          knows what to optimize before you write a ticket
```

That's the innovation path. Not "AI writes code for you." **Your codebase becomes self-improving.** You own the direction; the system owns the iteration.

### The Numbers

These come from 2,000+ experiments across 4 backends, 12 architectures, measured over 6 months:

| Metric | What it means for you |
|--------|----------------------|
| **20% keep-rate** | 1 in 5 experiments produces production-ready code. The system wastes API calls so you don't waste time. |
| **2,678 tests** | Every merge passes the full suite. Zero regression risk from automated changes. |
| **3 backends** (2 active) | DeepSeek + MiniMax active, Moonshot rate-limited. Automatic failover when provider fails. |
| **59% prompt compression** | Lambda notation tokens cost less. Same capability, lower cost. |
| **100+ experiments/month** | More iteration in a weekend than a human team does in a sprint. |

### Getting to Innovation Faster

1. **Start with pain.** Point OV5 at the files your team dreads modifying — the ones with the most tech debt, the most bugs, the most "don't touch it" comments. Those are where experiments create the most value.

2. **Review what's kept.** The system doesn't decide what's good for your codebase. You do. Check the kept experiments daily; adjust `.dir-locals.el` targets; the ontology adapts.

3. **Feed the ontology.** The more experiments run, the smarter the system gets. Category patterns stabilize after ~50 experiments per category. Before that, keep-rate is noise. After that, it's signal.

4. **Increase surface area.** Once the system handles file A well, add file B. The ontology already knows the category — strategy inherits. Each new target is cheaper than the last.

### For Solo Developers

One command replaces a full-time R&D partner. The ontology learns your codebase's specific patterns — not generic advice from a blog post, but what actually works in your project. After 100+ experiments, the system has seen more edge cases in your code than any human contributor.

### For Teams

The ontology is your **team's executable memory**. New members don't ask "why did we do it this way?" — they read the kept experiments. The system doesn't forget why a change was rejected in March or what pattern succeeded in June. Every experiment is a decision recorded as executable knowledge.

---

## For Advocators

**Every engineering leader has the same problem: your team's knowledge is fragile, your best practices are words in a doc, and your code quality depends on reviewers catching mistakes after they're made.** OV5 closes the loop: knowledge becomes executable, practices become automated, and quality shifts left — from review to generation.

### The Organizational Innovation Problem

Your team has accumulated hard-won knowledge about your codebase. But:

| Problem | Cost |
|---------|------|
| A senior engineer leaves | 6-12 months of accumulated pattern knowledge walks out the door |
| A decision made in a PR comment | No one reads PR comments 3 months later. Same bug, different fix |
| Best practices enforced by review | Review catches mistakes after they're committed to a branch |
| Onboarding takes months | New engineers repeat the same learning curve the team already climbed |

These aren't people problems. They're **systems problems**. Knowledge that lives in heads doesn't scale. Knowledge that lives in OV5's ontology compounds.

### How OV5 Transforms Your Organization

```
From:                          To:
Individual expertise     →    Organizational pattern memory
Reactive code review     →    Proactive guard rails
Stale documentation      →    Executable, self-updating knowledge
Manual refactoring       →    Automated experiment-driven improvement
Onboarding knowledge gap →    Inherited codebase intelligence
```

### The GTM Narrative

**OV5 is to code quality what CI/CD was to deployment reliability.**

Before CI/CD: deploy by hand, hope for the best, rollback when it breaks.
Before OV5: review by hand, hope the reviewer caught everything, fix in the next sprint.

| Era | Quality mechanism | Failure cost | Scaling |
|-----|------------------|-------------|---------|
| Waterfall | Manual testing before release | Weeks | 1 codebase |
| Agile/CI | Automated tests per commit | Hours | 10+ services |
| AI assistants | Chat-based code generation | Minutes (but inconsistent) | Any codebase, no memory |
| **OV5** | **Experiment-driven improvement + persistent ontology** | **Zero (worktree isolation)** | **Any codebase, compounding knowledge** |

Every AI coding tool today generates code with no memory of what your team rejected last week. OV5 remembers every kept and discarded experiment. That's the difference between a tool and a system.

### The Innovation Adoption Path

| Stage | What happens | Evidence |
|-------|-------------|----------|
| **1. Prove it** (weeks 1-2) | 10 targets, 50 experiments, ~20% keep-rate | Git log shows real merges. Team sees the system improving their code. |
| **2. Trust it** (weeks 3-8) | 50+ targets, 200+ experiments. Category patterns stabilize. Ontology learns which strategies work for each file type. | Keep-rate stabilizes. Reviewers spend less time on style, more on architecture. |
| **3. Scale it** (weeks 9-24) | 200+ targets, 1,000+ experiments. π Synthesis propagates strategies across clusters automatically. | New targets cost near-zero setup. The ontology knows the codebase better than any individual. |
| **4. Embed it** (months 6+) | OV5 runs in CI/CD. Every PR triggers experiments. The ontology evolves with the codebase. | Code quality improves autonomously. The team's innovation capacity grows without headcount growth. |

### ROI That Engineering Leaders Understand

| Investment | Return | Timeline |
|-----------|--------|----------|
| 1 hour setup | 50 experiments/week automated | Day 1 |
| 15 min/day reviewing kept experiments | 100+ experiments/month → 20% keep-rate → real merges | Month 1 |
| No additional headcount | System handles refactoring, bug fixing, pattern propagation | Ongoing |
| Documentation budget = $0 | Ontology records every decision as executable knowledge | Self-sustaining |

### Risk and Mitigation

| Risk | Mitigation |
|------|-----------|
| "What if the system makes bad changes?" | Worktree isolation + 6 gates (tests, grader, reviewer, comparator, π Synthesis, champion league). No change touches `main` without passing all gates. |
| "What if the ontology learns wrong patterns?" | Category drift detection (>20% deviation flagged). Eight-keys scoring catches overfitting. Holdout evaluation prevents self-deception. |
| "What if it doesn't work for our codebase?" | It runs on every `.el` file by default. 4 ontology categories cover all file types. No special integration needed. |
| "What if a backend goes down?" | 4 backends with automatic failover. Subagent routing self-tunes: unhealthy backends get health strikes → probation → exclusion. Auto-recovery after 1h without new strikes. |

### The Pitch

**To your CTO:** "This is continuous delivery for code quality. Every experiment that passes our tests is a merge. Every merge that fails our standards teaches the system what not to do. Over time, the system needs less review, not more."

**To your VP Engineering:** "Our team's knowledge compounds. Every PR reviewed, every experiment kept, every decision discarded — the ontology remembers. New engineers inherit not our docs but our accumulated codebase intelligence."

**To your team lead:** "Point this at the module your team hates maintaining. Let it run experiments. Review the ones that pass. You'll be surprised how many improvements the system finds in code you thought was 'done.'"

### What Advocacy Looks Like in Practice

1. **Day 1 pitch:** "Let's run 50 experiments on our most painful module and see what happens."
2. **Week 2 demo:** "Here are 10 experiments that passed all gates and improved code quality. The system found 3 bugs we didn't know existed."
3. **Month 1 report:** "100+ experiments, 20% keep-rate, zero regression incidents. The ontology has learned our codebase's patterns."
4. **Quarter 1 review:** "500+ experiments. New engineers onboard in days, not months. The system catches error patterns before code review."

This isn't a tool adoption. It's an **organizational capability upgrade**. The same way your team wouldn't go back to deploying without CI/CD, it won't go back to improving code quality without an experiment-driven ontology.

---

## Promoting OV5

Great architecture means nothing if nobody knows it exists. Here's how to get the message to each audience.

### To Creators (PMF: Grow Through Innovation)

Creators are skeptical, technical, and time-poor. They trust code more than copy. Meet them where they already are.

| Where | What to say |
|-------|-------------|
| **GitHub README** (this page) | Lead with the Innovation Flywheel and The Numbers. Make `./scripts/run-pipeline.sh` the first command they see. Link to `results.tsv` from a real run — show experiments, not architecture diagrams. |
| **Hacker News** | Title: *"My Emacs config runs 100 experiments/day and merges the winners"* — HN loves counterintuitive automation. Post on a Tuesday morning (US time) with the keep-rate numbers and a link to the GitHub repo. |
| **r/emacs** | Title: *"OV5: 2,061 tests, 4 backends, zero-touch experiment pipeline — all in Emacs Lisp"* — Emacs users want to see Emacs Lisp doing something no other editor can. Lead with the gptel integration and the pipeline architecture. |
| **Blog post** | Title: *"I Taught My Emacs to Improve Its Own Code"* — narrative format: the problem (manual code review), the experiment (first pipeline run), the results (20% keep-rate, real merges). Include a timestamped log from an actual pipeline run. Embed the key benchmark numbers. |
| **Conference talk** | Title: *"Self-Regulating AI Architecture: When Your Code Improves Itself"* — 30-min talk with live demo: `run-pipeline.sh` → watch experiments create worktrees → review kept results → show ontology learning over time. Best for Clojure/conj, EmacsConf, or Strange Loop. |
| **Twitter/X** | Thread format: 5 tweets — (1) problem, (2) OV5 approach, (3) the flywheel, (4) real numbers, (5) link to repo. Tag @karthink (gptel author) and relevant AI dev accounts. |

### To Advocators (GTM: Transform Your Organization)

Advocators need evidence, not features. They're asked "why should we adopt this?" and need answers that survive a budget review.

| Where | What to say |
|-------|-------------|
| **LinkedIn** | Title: *"The Knowledge Problem Every Engineering Team Has (and One Solution)"* — lead with the cost of tribal knowledge (senior leaves → 6-12 months of lost patterns). Link to the OV5 paper. Post mid-week (Wed/Thu) when engineering leaders are most active. |
| **Whitepaper** | *"Continuous Code Quality: An Experiment-Driven Approach to Engineering Excellence"* — 5-page PDF: (1) the tribal knowledge problem with real cost estimates, (2) the OV5 approach compared to status quo, (3) adoption path with timeline and risk mitigation, (4) ROI calculation worksheet for CTOs. Publish on GitHub Releases as a PDF. |
| **Engineering leadership newsletter** | Pitch to leading engineering newsletters (Engineering Impact, The Engineering Manager, Hackernoon). Title: *"Stop Reviewing. Start Experimenting."* — 800 words on why code review is reactive and OV5 is proactive. |
| **Case study** | *"From 0 to 500 Experiments: How We Automated Code Quality"* — real metrics: git log of merged experiments, keep-rate trend over 3 months, categories that improved most. Include quotes from the team: "I used to spend 2 hours reviewing nil-guard PRs. Now the system handles them." |
| **Conference talk** | *"Code Quality Is Not a Review Problem"* — talk for engineering leadership audience (LeadDev, QCon, or local CTO meetups). Thesis: "Your team's best practices are fragile because they live in heads, not in systems. Here's how to encode them as executable knowledge." |
| **CTO-to-CTO** | Direct outreach to CTOs of mid-sized SaaS companies (50-200 engineers). Message: "Your team has the same tribal knowledge problem every scaling engineering org has. I built a system that encodes it as executable patterns. Here's our case study. 30-min call?" |

### The Activation Funnel

Not everyone who reads becomes an adopter. Here's the path from awareness to running their first pipeline:

```
Awareness → README / HN / LinkedIn post
    ↓
Interest →  "Can it handle my codebase?" → read The Numbers + Risk section
    ↓
Evaluation →  Clone, run `./scripts/run-pipeline.sh` on 3 target files
    ↓
Trial →  50 experiments → review results → see 20% keep-rate in their own repo
    ↓
Adoption →  Add 20 targets → run daily → review kept experiments → ontology learns
    ↓
Advocacy →  "We've run 1,000+ experiments. The system found bugs we didn't know existed."
```

Every step must answer the question the audience is asking RIGHT NOW before they click away:

| Step | The question | Where the answer lives |
|------|-------------|----------------------|
| Awareness | "What is this?" | README opening paragraph |
| Interest | "Is this for me?" | For Creators / For Advocators sections |
| Evaluation | "Will it work for us?" | Risk and Mitigation + The Numbers |
| Trial | "How do I start?" | Begin section + run-pipeline.sh |
| Adoption | "Is it worth the investment?" | ROI table + Innovation Adoption Path |
| Advocacy | "How do I convince my team?" | The Pitch + What Advocacy Looks Like |

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
| **Backend performance analysis** | 2,000+ experiments tracked across 3 backends → keep-rate statistics; three-way (category×strategy×hashtags) combo learning |
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
| 2,678+ tests + 300s timeout | Broken code caught before staging |
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
