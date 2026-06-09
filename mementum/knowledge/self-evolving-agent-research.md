---
title: Self-Evolving Agent Research Papers (May-June 2026)
status: active
category: research
tags: self-evolution, autonomous-agents, MOSS, Sibyl, APEX, TSP, exploration-collapse, source-level-evolution, secure-code
related: OV5 architecture, ontology graph, mementum protocol, self-heal-semantic
created: 2026-06-09
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

## Summary: Action Items for OV5

| Paper | Key Lesson | OV5 Action Item |
|-------|------------|-----------------|
| MOSS | Batch anchoring before evolution | Group similar failures before proposing fixes |
| MOSS | Deterministic multi-stage pipeline | Formalize evolution stages with explicit ordering |
| Sibyl | Explicit trial-to-behavior conversion | Formalize ontology updates as auditable conversion units |
| Sibyl | Recovered-failure registry | Track how failures were handled (blocked/downgraded/routed) |
| APEX | Explicit strategy DAG | Add prerequisite edges to ontology to prevent exploration collapse |
| APEX | Fork Discovery | Systematically identify unexplored ontology gaps |
| TSP | Fine-grained risk nodes | Add "risk node" detection to self-heal-semantic module |
| TSP | Self-play at decision points | Generate secure + vulnerable variants at critical points |
| TSP | On-policy negative examples | Use model's own insecure generations as training signal |
| TSP | Language-agnostic principles | Learn abstract security principles from experiment outcomes |

## OV5's Unique Advantages

1. **Git worktree isolation** — No container overhead, native git integration
2. **Mementum protocol** — Cross-session memory via git-based persistence
3. **Source-level + text-level evolution** — Evolves both code AND prompts/memory
4. **Ontology graph** — Rich relational structure beyond simple strategy maps
5. **Self-heal semantic audit** — Automatic detection and fixing of code bugs (7 audit checks)
6. **Cross-session learning** — Mementum persists learning across daemon restarts

---

*Synthesized from arXiv papers 2605.22794, 2605.22343, 2605.21240, 2606.03489v1*
