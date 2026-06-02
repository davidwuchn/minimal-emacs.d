# OUROBOROS-V5: Self-Regulating AI Architecture

> **The snake that researches what to eat, executes what it learned, and feeds outcomes back into its own appetite.**
>
> **Cost:** ~$0.50-2.00 per pipeline run (3 backends, cache-aware pricing). **Safety:** Git worktree isolation + 6 gates (tests, grader, reviewer, comparator, π Synthesis, champion league) — no change touches `main` without passing all gates. **Portability:** P(λ)=90.7% across 4 backends — lossless provider migration.
>
> **First run:** [`./scripts/run-pipeline.sh`](scripts/run-pipeline.sh) — initializes itself. After that, the snake feeds itself.
>
> Built on [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d) + [gptel](https://github.com/karthink/gptel). 3 pipeline runs/day (Linux: every 4h) + hourly self-evolution + watchdog every 30min. The snake eating its own tail — every subsystem improves every other subsystem.

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

**Troubleshooting:** Pipeline stuck at "selecting"? Check `gptel-auto-workflow-status` and `var/log/emacs-*.log`. Provider rate-limited? The system auto-failovers; check `gptel-auto-workflow--rate-limited-backends`.

**Example output** (from a real run):
```
[auto-workflow] Starting 2026-06-01T154953Z-eac5 with 5 targets
[subagent] executor using DashScope/qwen3.6-plus
[auto-experiment] ✓ Tests passed
[auto-experiment] ✓ Experiment kept — merged to staging
===RESULT=== {"metric":"evolution-cycle","value":0.107}
```

**Daily routine:**
```
1. gptel-auto-workflow-status          # phase: idle/running/error
2. git log --oneline -10               # review kept experiments
3. tail var/log/emacs-*.log            # skim for errors
4. cat var/tmp/experiments/*/results.tsv | head -3  # latest keep-rate
```
> **What's normal:** Phase cycles idle → selecting → running → idle. Timeouts and rate-limits appear in logs but the system auto-recovers. Keep-rate should trend toward 20% after ~50 experiments per category.
> **What's not:** 0 kept for 3+ consecutive runs (check provider routing). Same error across all backends (likely code, not provider).

---

## For Users

You're running OV5. Here's what to expect day-to-day.

**Signs of health:** Keep-rate trending toward 20%. Fewer "prompt is empty" or "executor-callback" errors over time. Backend routing self-tunes away from failing providers. Git log shows real merges from experiments.

**Signs to investigate:** 0 kept for 3+ consecutive runs with different targets. Keep-rate suddenly drops after adding a new target category. Same experiment consistently fails on all backends (likely a prompt or strategy issue, not provider).

**Meta: is the system improving?** Track keep-rate per category weekly. Early experiments are exploration — noise is normal. After ~50 experiments/category, trends become signal. If keep-rate plateaus below 15%, check if targets match ontology categories.

**Cowork with AI coding agents:** Run `./scripts/setup-ov5-cowork.sh` to install OV5 integration for OpenCode, Claude Code, Cursor, and MCP-compatible agents. Lets your coding agent trigger experiments and review results via emacsclient.

**Quick triage:**
| Symptom | Likely cause | Check |
|---------|-------------|-------|
| 0 targets selected | Analyzer failed / rate-limited | `gptel-auto-workflow--rate-limited-backends` |
| All experiments discarded | Baseline tests failing | Test suite output in daemon log |
| Daemon unresponsive | ERT test run (can take 2min) | Wait; check `ps aux | grep emacs` |
| "prompt is empty" errors | Strategy analysis returned no patterns | Usually transient — next cycle often recovers |

---

## Configuration

**Targets:** Set `gptel-auto-workflow-targets` in `.dir-locals.el` or `post-init.el`. Targets can be file paths, directories, or glob patterns. Default: all `.el` files in `lisp/modules/`.

**Skipping targets:** The system skips files that are saturated (≥10 experiments), have repeated failure patterns, or fail precondition checks. Add unwanted targets to `gptel-auto-workflow--skip-headless-target-p` logic.

**Backends:** Provider routing is auto-evolved via `assistant/strategies/provider-routing/backend-preference.el`. Override in `post-init.el` by setting `gptel-auto-workflow-headless-subagent-fallbacks`.

**Timeline:** First experiment completes in ~30min (analyzer→executor→grader→review). First meaningful data in ~24h (5+ targets, 50+ experiments). Keep-rate trends stabilize after ~50 experiments per category.

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
| Wondering "did I break anything?" | 2,678+ tests run before every merge | Ship with confidence, not hope |
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

These come from 2,000+ experiments across 3 backends, 12 architectures, measured over 6 months:

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
| "What if a backend goes down?" | 3 backends with automatic failover. Subagent routing self-tunes: unhealthy backends get health strikes → probation → exclusion. Auto-recovery after 1h without new strikes. |

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

See [docs/promoting.md](docs/promoting.md) for channel-specific messaging (HN, LinkedIn, conference talks, etc.).

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
| **Test execution** | Did 2,678+ tests pass? | Experiment discarded, pattern learned |
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

All 97 `.el` files pass `byte-compile-error-on-warn t`. Prompt construction migrated from `{{mustache}}` template substitution to EDN plist → `resolve` → λ notation (deterministic, zero LLM calls for rendering).

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

OV5 currently runs on external APIs (DeepSeek, MiniMax, DashScope). Future work: verbum integration for local deterministic execution — see [verbum](https://github.com/davidwuchn/verbum).

---

Built on [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d). Extended with gptel, nucleus statecharts, mementum memory, verbum operational taxonomy, Semantica ontology, AutoGo competitive gating, LogMap inverted indexing and repair, Allium behavioral compilers. 37 patterns across 4 frameworks. The art grows with its practitioner.
