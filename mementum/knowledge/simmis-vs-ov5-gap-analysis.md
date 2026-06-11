---
title: "Simmis Stack vs OV5: Architectural Gap Analysis"
date: 2026-06-11
status: active
category: architecture
tags: [simmis, ov5, gap-analysis, datalog, bayesian-inference, causal-graphs, verification]
related: [self-evolving-agent-research, research-openmythos-looped-ov5, memgraphrag-gap-analysis, self-healing-architecture, dual-mayor-architecture]
depends-on: []
---

# Simmis Stack vs OV5: Architectural Gap Analysis

## TL;DR

Both systems share the same meta-belief: many small tries beat one perfect answer.

The difference is what they make cheap:

- **Simmis** makes it cheap to branch and reason over alternative worlds.
- **OV5** makes it safe to run real code interventions and learn from them.

**Core conclusion:** Simmis is ahead on substrate quality. OV5 is ahead on operational closure. OV5's biggest missing layer is a **first-class, branchable world model** under the existing git/worktree pipeline.

| System | Design center | Current strength |
|---|---|---|
| Simmis | Simulate before acting | Branchable reasoning substrate |
| OV5 | Act safely, then learn | Production self-improvement loop |

## Gap analysis

### 1. Canonical world state (gap: very high)

- **Simmis has:** Immutable Datalog via Datahike, coordinated branching across SQL/vector/full-text via Yggdrasil. One branchable substrate for memory.
- **OV5 has:** Git for code, markdown mementum files, `var/context/*.sexp` sidecars, JSON memory-schema index, TSV experiment history, OWL/SHACL exports.
- **Gap:** OV5 has multiple persistence surfaces, but no single immutable query layer spanning all of them. It can branch code, but not "the whole world" it reasons over.
- **Recommendation:** Build an **OV5 World Store** behind brepl. Keep git as source-of-truth for code, but mirror experiment/task/context/memory/approval facts into a branchable Datalog store. Every experiment should have both a `git-worktree-id` and a `world-branch-id`.

### 2. Branching semantics / computation context (gap: very high)

- **Simmis has:** Copy-on-write branching of data and O(1) forking of execution context in Spindel; signals, caches, and continuations are values.
- **OV5 has:** Git worktrees, isolated worktree buffers, staging, and per-experiment sidecars.
- **Gap:** OV5 forks the filesystem, not the runtime state. Prompt context, retrieved memory, router state, caches, and intermediate reasoning are not first-class branchable objects.
- **Recommendation:** Add **task-context snapshots**: prompt inputs, retrieved facts, router scores, cache keys, tool outputs, and intermediate analysis. Fork them alongside the git worktree.

### 3. Inference and uncertainty (gap: high)

- **Simmis has:** `sample` / `observe`, importance sampling, SMC, MCMC, posterior distributions, sequential Bayesian updating.
- **OV5 has:** Keep-rate tracking, recency decay, grading heuristics, complexity gate, and a small Bayesian-style cold-start floor in routing.
- **Gap:** OV5 mostly makes thresholded point decisions. It does not maintain calibrated posteriors over strategy quality, backend quality, regression risk, or expected utility.
- **Recommendation:** Add a **Bayesian decision layer**:
  - Beta-Bernoulli or hierarchical posteriors for backend/category/strategy keep-rates
  - Credible intervals in routing and approval views
  - Thompson sampling or upper credible bound for explore/exploit

### 4. Causality and intervention semantics (gap: high)

- **Simmis has:** Explicit DAGs and a first-class do-operator (`intervene!`) for counterfactual reasoning.
- **OV5 has:** Causal-chain sidecars, Floyd-Warshall over experiment sequences, and a simple experiment causal graph. It also runs real sandboxed interventions on code.
- **Gap:** OV5 has **interventional data**, but not an explicit structural causal model. Current causal reasoning is mostly retrospective path analysis, not "what if we intervene on X?" semantics.
- **Recommendation:** Add a **causal DAG layer** over: target type, strategy class, backend, complexity delta, test outcome, keep decision, observed impact. Then distinguish `observe` from `intervene` in experiment logs and planning.

### 5. Verification and correctness (gap: medium-high)

- **Simmis has:** Ansatz: Clojure programs checked against Lean 4's kernel where proof matters.
- **OV5 has:** ERT-heavy verification, byte-compile discipline, self-heal semantic, paren/load gates, staging baseline comparison, sandboxing, approval queue.
- **Gap:** OV5 is strong on empirical verification, weak on machine-checked semantic guarantees. Critical transforms are tested and rolled back, but not proven.
- **Recommendation:** Add **proof islands**, not whole-system proofs. Start with policy engine invariants, worktree/boundary invariants, lambda prompt compiler invariants, self-heal transform safety properties.

### 6. Agent substrate / task model (gap: medium-high)

- **Simmis has:** Dvergr agents acting inside the same versioned substrate humans use; each action is a bounded task that forks the world and is accepted or rejected.
- **OV5 has:** Subagents, skills, monitoring agent, worktree execution, approval queue, git-based accept/reject path.
- **Gap:** In OV5, agent actions are spread across prompts, buffers, worktrees, logs, and files. They are not first-class typed task objects over a shared world substrate.
- **Recommendation:** Represent each agent action as a **Task record** with: world branch, git worktree, read-set, retrieved facts, prompt, diff, evidence, decision. Persist this in the world store.

### 7. Memory / retrieval coherence (gap: medium)

- **Simmis has:** One branch model across memory, search, and retrieval surfaces.
- **OV5 has:** Memory-schema triple extraction, stable schema promotion, conflict detection, graph retrieval, code-memory links, context sidecar query/search.
- **Gap:** OV5 has strong pieces, but they are derived indexes over files, not one transactional substrate. Retrieval is only partially branch-aware.
- **Recommendation:** Unify mementum, context sidecars, experiment results, ontology facts, and approval decisions into one **branch-aware retrieval layer** with provenance and validity intervals.

### 8. Numerical modeling / differentiable compute (gap: medium)

- **Simmis has:** Raster for fast numerics, autodiff, and Bayesian modeling at JVM/GPU speed.
- **OV5 has:** Deterministic scoring code, heuristic analytics, and a Clojure brepl bridge.
- **Gap:** OV5 lacks a native numerical modeling plane for fitting probabilistic or causal models efficiently.
- **Recommendation:** Do serious inference/model fitting in **Clojure via brepl**, not raw Elisp. Elisp should remain control plane; Clojure should become model plane.

## Where OV5 is already ahead

1. **Live production loop** - OV5 is already running real code experiments, not just modeling possible worlds.
2. **Safety envelope** - Worktrees, gates, sandboxes, approval queue, and regression checks are operational.
3. **Self-healing evaluator stack** - OV5 repairs parts of its own execution/evaluation path.
4. **Backend routing with real telemetry** - OV5 has health, keep-rate, cost, and cooldown logic in production.
5. **Dual-runtime path exists now** - The brepl bridge makes a Clojure substrate an additive move, not a rewrite.

## Existing OV5 footholds to build on

- `gptel-auto-workflow-context-database.el` - Per-experiment business rationale, causal chain, dependencies
- `gptel-auto-workflow-memory-schema.el` - Triple extraction, stable schemas, conflict detection, graph retrieval
- `gptel-auto-workflow-knowledge-reasoning.el` - Horn SAT, Floyd-Warshall, Allen intervals, OWL/SHACL
- `gptel-auto-workflow-ontology-router.el` - Recency-weighted routing with Bayesian-style cold-start floor
- `gptel-ext-brepl.el` - Existing Clojure bridge for a deeper model/state layer

## What to build next

| Priority | Build | Why | Minimal slice |
|---|---|---|---|
| P0 | **OV5 World Store** | No canonical branchable state | Datahike-side store via brepl; ingest experiment results, context sidecars, memory triples, approval decisions |
| P0 | **Bayesian Router v1** | Replace heuristic confidence with calibrated uncertainty | Beta posteriors for backend x category x strategy keep-rate; Thompson sampling |
| P1 | **Causal DAG v1** | Turn post-hoc causal stories into intervention planning | Static DAG over strategy/backend/complexity/test/keep/impact |
| P1 | **Task-context snapshots** | Branch computation, not just files | Persist prompt inputs, retrieved memories, router scores, tool outputs per experiment |
| P2 | **Proof islands** | Formal guarantees where failures are most expensive | Verify policy engine, boundary invariants, prompt compiler |
| P3 | **Numeric model plane** | Richer simulation and posterior fitting | Host probabilistic and causal scoring kernels in Clojure via brepl |

## Recommended architecture move

**Best hybrid:** keep **Emacs Lisp as control plane** and add **Clojure as model plane**.

- **Elisp stays responsible for:** UX, orchestration, gates, git/worktrees, approval flow, self-heal integration
- **Clojure takes on:** world store, probabilistic inference, causal models, numeric simulation, proof-adjacent kernels

That gives OV5 the missing Simmis-style substrate without throwing away the production loop that already works.

## Net assessment

Simmis is ahead on **branchable semantics, uncertainty, and causal reasoning**.
OV5 is ahead on **cybernetic closure, safety, and real self-improving operation**.

The highest-leverage move is not "become Simmis." It is:

**branch the world in parallel with the repo.**

Keep git worktrees for code. Add a branchable world store for reasoning. Then let Bayesian and causal models sit underneath OV5's existing experiment engine.

## References

- https://simm.is/stack/
- https://simm.is/notes/bayesian-inference-in-pictures
- https://simm.is/notes/reading-a-causal-graph
- https://simm.is/notes/copy-on-write-branching
- `OUROBOROS-V5.md`
