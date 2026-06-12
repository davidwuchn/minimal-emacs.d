---
title: Self-Evolving Agent Research Papers (May-June 2026)
status: active
category: research
tags: self-evolution, autonomous-agents, MOSS, Sibyl, APEX, TSP, SkillOpt, verbum, exploration-collapse, source-level-evolution, secure-code, skill-self-evolution, crystal-equation
related: OV5 architecture, ontology graph, mementum protocol, self-heal-semantic, verbum-ov5-gap-analysis, verbum-audit-methodology
created: 2026-06-09
updated: 2026-06-12
---

# Self-Evolving Agent Research Papers (May-June 2026)

Four highly relevant papers from May-June 2026 on self-evolving autonomous agents.

## 1. MOSS: Source-Level Self-Evolution (2605.22794)

**Key Insight:** Most self-evolving agents only evolve **text artifacts** (prompts, skills, memory schemas) and leave the **agent harness untouched**. Since routing, hook ordering, state invariants, and dispatch live in code, an entire class of structural failure is physically unreachable from the text layer.

**MOSS Approach:**
- Source-level adaptation is **Turing-complete** — strict superset of text-mutable scope
- Anchored to production-failure evidence batches
- Verifies candidates by replaying batch against candidate image
- Result: 0.25 → 0.61 grader score in single cycle

**OV5 Comparison:**

| Aspect | MOSS | OV5 |
|--------|------|-----|
| Evolution medium | Source code rewriting | Source code + prompts + memory |
| Failure evidence | Batch replay | TSV results + grader scores |
| Verification | Container swap + health probes | Git worktree isolation + test suite |
| Rollback | Health-probe gated | Git revert + ontology learning |

**What OV5 does better:**
- Git worktree isolation — no container overhead
- Ontology learning — every outcome updates the graph
- Mementum memory — cross-session learning via git

**What OV5 could learn:**
- Batch anchoring — curate failure batches before evolution
- Deterministic multi-stage pipeline — explicit stage ordering

## 2. Sibyl-AutoResearch: Trial-and-Error Harnesses (2605.22343)

**Key Insight:** Executable workflows don't produce research judgment. Current systems lose trial experience: weak evidence becomes prose, pilot signals become broad claims, memory remains textual, and **recurring process failures do not change later behavior**.

**Sibyl's Two Conversion Units:**
1. **Trial-to-behavior conversion** — links trial signals to later research actions
2. **Trial-to-harness-behavior conversion** — links recurring process failures to system updates

**Result:** Median latency of **1 iteration** for conversion events; max 3 iterations.

**OV5 Comparison:**

| Aspect | Sibyl | OV5 |
|--------|-------|-----|
| Trial preservation | Positive + negative outcomes | Kept + discarded experiments |
| Lesson routing | Planning, validation, claim scope | Ontology graph + strategy preferences |
| Harness repair | trial-to-harness-behavior | Self-heal semantic audit + fixers |
| Failure registry | 5 failure classes tracked | 16 systemic failure patterns detected |

**What OV5 could learn:**
- Explicit conversion formalization — formalize ontology updates as auditable units
- Recovered-failure registry — track how failures were handled

## 3. APEX: Exploration Collapse (2605.21240)

**Key Insight:** Self-evolving agents suffer from **exploration collapse**: as memory grows, behavior concentrates around familiar high-reward routines, reducing chance of discovering better alternatives.

**APEX Solution:**
- Builds explicit **strategy map** — DAG of milestones with prerequisite dependencies
- **Fork Discovery** — expands map with evidence-grounded unexplored directions
- **Policy Selection** — balances exploration and exploitation during planning

**OV5 Comparison:**

| Aspect | APEX | OV5 |
|--------|------|-----|
| Strategy space | Explicit DAG of milestones | Ontology graph (implicit strategy space) |
| Exploration | Fork Discovery | Frontier filtering + category budgets |
| Exploitation | Policy Selection | Keep-rate optimization |
| Collapse prevention | Explicit unexplored directions | Category saturation detection |

**What OV5 could learn:**
- Explicit strategy DAG — add prerequisite edges to ontology
- Fork Discovery — systematically identify unexplored ontology gaps

## 4. TSP: Tree-like Self-Play for Secure Code (2606.03489v1)

**Key Insight:** Current alignment techniques (SFT, RL) apply coarse-grained optimization at the sequence level, failing to address the localized nature of security flaws where a single incorrect token choice can compromise an entire program. TSP reframes secure code generation as a fine-grained sequential decision process by identifying "CWE Risk Nodes" — critical decision points where vulnerabilities emerge.

**TSP Approach:**
- Constructs decision tree where model explores branching trajectories (secure "golden paths" + vulnerable variants)
- Self-play at risk nodes: model uses its own insecure branches as "opponent"
- Dense, on-policy learning signal forces self-correction at critical decision nodes
- Result: 57.0% → 75.8% security pass rate; 24.5% reduction in unseen CWE vulnerabilities
- Cross-language transfer: C/C++ security principles transfer to Python, Go, JavaScript

**OV5 Comparison:**

| Aspect | TSP | OV5 |
|--------|-----|-----|
| Learning granularity | Token-level risk nodes | Experiment-level kept/discarded |
| Negative examples | Self-generated vulnerable variants | Discarded experiments |
| Knowledge persistence | Model weights | Git-based mementum + ontology |
| Evolution medium | Source code | Source code + prompts + memory |
| Cross-context transfer | Language-agnostic security principles | Ontology graph relationships |
| Isolation | None (training) | Git worktree isolation |

**What OV5 does better:**
- Git worktree isolation — each experiment runs in isolated worktree
- Ontology graph — rich relational structure beyond simple decision trees
- Cross-session memory — Mementum protocol persists learning across sessions
- Source-level + text-level evolution — evolves both code AND prompts/memory
- Self-heal semantic audit — automatic detection and fixing of code bugs

**What OV5 could learn:**
- Fine-grained failure analysis — identify specific "risk nodes" in code where failures emerge
- Self-play at decision points — generate both secure and vulnerable variants at critical points
- On-policy negative examples — use model's own insecure code generations as training signal
- Language-agnostic principles — learn abstract security principles that transfer across contexts

## 5. SkillOpt: Executive Strategy for Self-Evolving Agent Skills (2605.23904)

**Key Insight:** Most agent skills are hand-crafted, one-shot generated by a strong LLM, or evolved through loosely controlled self-revision. SkillOpt treats the **skill document as the trainable state** of a frozen agent and optimizes it with deep-learning discipline — never touching model weights.

**SkillOpt Approach:**
- **Target / optimizer split** — target executes tasks with the current skill; optimizer analyzes trajectories and proposes bounded add/delete/replace edits
- **Validation gate** — candidate skill accepted only if it strictly improves a held-out selection score
- **Learning-rate budget** — `optimizer.learning_rate` caps edits per step; scheduler (constant / linear / cosine / autonomous)
- **Slow update** — epoch-boundary longitudinal guidance written to a protected region (`<!-- SLOW_UPDATE_START --> … <!-- SLOW_UPDATE_END -->`), counters cross-epoch forgetting
- **Meta skill** — optimizer-side cross-epoch memory fed back into reflection
- **SkillOpt-Sleep** — nightly offline cycle: harvest session transcripts → mine recurring tasks → replay offline → reflect → bounded edit → gate on real held-out tasks → stage proposal → user adopt
- **Deployable artifact** — compact `best_skill.md` (300–2,000 tokens)

**OV5 Comparison:**

| Aspect | SkillOpt | OV5 |
|--------|----------|-----|
| Evolution target | Single skill document | Multiple surfaces: `assistant/skills/`, `.opencode/skills/`, `~/.config/opencode/skills/`, `.agents/skills/` |
| Training signal | Scored rollouts on benchmark / real tasks | Experiment keep/discards + skill-graph edge weights |
| Edit generation | Optimizer model → bounded patches | LLM variant generator + manual `skill-creator` / `skills-refiner` |
| Validation gate | Held-out selection split strictly improves | OpenCode eval assertions + human-gated approval queue |
| Momentum / memory | Slow-update protected region + meta skill | Skill graph (`var/tmp/skill-graph.eld`) + mementum memories |
| Continuous operation | SkillOpt-Sleep nightly offline loop | Hourly evolution cron (feature-flagged off by default) |
| Deployment artifact | `best_skill.md` | Champion variant promoted to canonical `SKILL.md` |
| Rollback / safety | Gate reject + rejected-edit buffer | Git revert + high-risk worktree validation |

**What OV5 does better:**
- Multi-surface skill management with YAML frontmatter discovery and ontology-driven routing
- Git-based cross-session persistence (mementum protocol)
- Source-level self-heal in addition to text-level skill evolution
- Human-in-the-loop approval queue for promotions
- No dependency on a fixed benchmark adapter; skills apply to open-ended Emacs/OpenCode tasks

**What OV5 could learn:**
- Strict validation gating on held-out real tasks, not just surface assertion patterns
- Bounded edit budget / learning-rate scheduler for skill mutations
- Rejected-edit buffer to avoid re-proposing bad edits
- Protected slow-update guidance region inside skills for cross-epoch memory
- SkillOpt-Sleep style nightly consolidation from session transcripts
- Separate optimizer/target models for cost-effective skill evolution
- Multi-rollout contrastive reflection (compare high- vs low-scoring attempts of the same task)
- Multi-objective reward (accuracy + tokens + latency)

## 6. verbum: Distilling the Lambda Compiler (198+ sessions)

**Key Insight:** Three converging lines — math (Montague, DisCoCat), empirics (nucleus P(λ)=90.7%), architecture (MERA negative result) — point at one object: the language compressor is a typed lambda calculus interpreter. verbum extracts that interpreter as a portable tensor artifact.

**Core innovations:**
- **Crystal equation** λ_k = C·φ^(−s·β_k): governs LLM computation geometry; r=0.998 KIBC across 200× range
- **Computing fraction** s=n/(n+1): predicts eigenvalue ratios from combinator count (<0.04% err)
- **Statechart**: 2n-state absorbing Markov chain; halt probability, reduction length derive from φ
- **Score Matching Loss**: per-layer cos sim prevents compensating errors; 35% better than CE-only
- **2-Mirror TQ**: sign-magnitude quantization, recon_cos=0.970 @ 4.0 bits vs Q4 0.95 @ 4.5 bits

**Latest (June 2026):** Continuations working at tensor level (15 tests green). 3-family function shape discovered in routing register: Composition (B,D,S), Selection/Identity (K,I,C), Recursion (Y,W,WHNF). Map=Y∘B, fold=Y∘(C/B)+K. Functions visible only in routing register — validating the two-registers theory.

**OV5 transferable gaps (7):** See [verbum-ov5-gap-analysis.md](verbum-ov5-gap-analysis.md). P0: provenance.json per experiment, pipeline statechart. P1: per-gate score vectors, Kronecker factorization.

## Summary: Action Items for OV5

| Paper | Key Lesson | OV5 Action Item |
|-------|------------|-----------------|
| MOSS | Batch anchoring before evolution | Group similar failures before proposing fixes |
| MOSS | Deterministic multi-stage pipeline | Formalize evolution stages with explicit ordering |
| Sibyl | Explicit trial-to-behavior conversion | ✅ **IMPLEMENTED** — `gptel-ext-conversion-unit.el` tracks every ontology update as an auditable unit with trial-id, before/after state, timestamp, and validation status |
| Sibyl | Recovered-failure registry | Track how failures were handled (blocked/downgraded/routed) |
| APEX | Explicit strategy DAG | Add prerequisite edges to ontology to prevent exploration collapse |
| APEX | Fork Discovery | Systematically identify unexplored ontology gaps |
| TSP | Fine-grained risk nodes | Add "risk node" detection to self-heal-semantic module |
| TSP | Self-play at decision points | Generate secure + vulnerable variants at critical points |
| TSP | On-policy negative examples | Use model's own insecure generations as training signal |
| TSP | Language-agnostic principles | Learn abstract security principles from experiment outcomes |
| SkillOpt | Strict held-out validation gate | Gate skill promotions on real held-out task performance, not just assertion checks |
| SkillOpt | Bounded edit budget / LR scheduler | Cap skill mutations per cycle and decay/schedule the budget |
| SkillOpt | Slow-update protected region | Add cross-epoch guidance field to canonical skills |
| SkillOpt | Rejected-edit buffer | Track rejected skill edits to avoid re-proposing them |
| SkillOpt | SkillOpt-Sleep nightly consolidation | Harvest session transcripts, replay recurring tasks, gate updates, stage for adoption |
| verbum | Per-experiment provenance | Add provenance.json with git SHA, pkg versions per experiment |
| verbum | Pipeline statechart | Build formal statechart from TSV data to predict bottlenecks |
| verbum | Per-gate score vectors | Prevent compensating errors with 7-dim gate-score vectors |

## OV5's Unique Advantages

1. **Git worktree isolation** — No container overhead, native git integration
2. **Mementum protocol** — Cross-session memory via git-based persistence
3. **Source-level + text-level evolution** — Evolves both code AND prompts/memory
4. **Ontology graph** — Rich relational structure beyond simple strategy maps
5. **Self-heal semantic audit** — Automatic detection and fixing of code bugs (7 audit checks)
6. **Cross-session learning** — Mementum persists learning across daemon restarts

---

*Synthesized from arXiv papers 2605.22794, 2605.22343, 2605.21240, 2606.03489v1, 2605.23904, Microsoft SkillOpt, and the verbum project (github.com/davidwuchn/verbum, 198+ sessions)*
