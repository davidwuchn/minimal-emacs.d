---
title: "Planning Graph & PlanSearch: Two Approaches OV5 Lacks"
status: open
category: research
tags: [planning, code-generation, search, diversity, graph-representation]
related: [self-evolving-agent-research, ontology-routing]
depends-on: []
---

# Planning Graph & PlanSearch: Two Approaches OV5 Lacks

## Papers Studied

### 1. RPG: Repository Planning Graph (arXiv:2509.16198)
**Microsoft Research, Sep 2025**

**Core insight:** Replace free-form natural language planning with explicit graph representation for repository-level code generation.

**Key mechanisms:**
- **Two-level planning:** Proposal-level (what to build) → Implementation-level (how to build)
- **Structured graph:** Nodes = capabilities/files/functions, Edges = data flows/dependencies
- **Topological ordering:** Dependencies precede dependents in generation order
- **Graph-guided localization:** Structural guidance when implementing changes

**Results:**
- 3.9x larger repos than Claude Code (36K LOC vs 9K LOC)
- 81.5% functional coverage (vs 54.2% for Claude Code)
- 69.7% test accuracy (vs 33.9% for Claude Code)
- Near-linear scaling of functionality with repository size

**Why it works:**
- Natural language plans are ambiguous and drift across iterations
- Explicit graph enforces consistency and dependency tracking
- Machine-interpretable blueprint > free-form prose for long-horizon planning

---

### 2. PlanSearch: Planning in Natural Language Improves LLM Search (arXiv:2409.03733)
**Scale AI, Sep 2024**

**Core insight:** Search over diverse natural language plans before code generation increases solution diversity and improves pass rates.

**Key mechanisms:**
- **Observations → Plans → Solutions pipeline:** Generate diverse observations about problem → construct plans from observations → search over plans
- **Diversity-aware search:** Explicitly maximize plan diversity to avoid repeated sampling of similar incorrect solutions
- **Plan-level exploration:** Search in plan space (natural language) rather than code space

**Results:**
- Pass@200 of 77.0% on LiveCodeBench (vs 60.6% with repeated sampling)
- Pass@1 of 41.4% without search
- Performance gains predictable as function of plan diversity

**Why it works:**
- LLMs lack diversity when repeatedly sampling code (similar incorrect generations)
- Searching over plans in natural language explores more diverse solution space
- Diversity over generated ideas directly predicts performance gains

---

## OV5 Current Architecture

OV5 is a self-improving loop: research → experiment → verify → learn.

**Current planning approach:**
- Target selection (ontology-routed)
- Hypothesis generation (natural language, one per target per cycle)
- Implementation (git worktree isolation)
- 7 gates (test execution, AI grading, complexity, review, synthesis, champion league)
- Learning (mementum, ontology updates)

**Strengths:**
- Autonomous self-improvement loop
- Ontology-based routing and categorization
- Strong quality gates
- Memory across sessions (mementum)
- Multi-backend failover

**Weaknesses (vs RPG + PlanSearch):**
- No structured planning representation
- No diversity-aware search over plans
- No two-level planning (proposal vs implementation)
- No graph-guided localization
- No plan-level search (only searches over backends/models)

---

## Gap Analysis

### Gap 1: No Structured Planning Representation (vs RPG)

**OV5:** Free-form hypotheses in natural language
**RPG:** Explicit graph with nodes (capabilities, files, functions) + edges (data flows, dependencies)

**Impact:**
- Plans can drift across iterations (RPG's key finding)
- No explicit dependency tracking between experiments
- No topological ordering of implementation steps
- Ambiguity in long-horizon planning

**What OV5 lacks:**
- Machine-interpretable blueprint for multi-step changes
- Explicit representation of data flows between modules
- Structural guidance when implementing changes across files

---

### Gap 2: No Diversity-Aware Search (vs PlanSearch)

**OV5:** One hypothesis per target per cycle, no explicit diversity mechanism
**PlanSearch:** Generate diverse observations → construct diverse plans → search over plan space

**Impact:**
- Repeated sampling of similar approaches (PlanSearch's key problem)
- No explore-exploit over plan space
- No mechanism to maximize plan diversity before implementation

**What OV5 lacks:**
- Observations → plans → solutions pipeline
- Explicit diversity metric for generated hypotheses
- Plan-level search (OV5 only searches over backends/models)

---

### Gap 3: No Two-Level Planning (vs RPG)

**OV5:** Jumps from target selection → hypothesis → implementation
**RPG:** Proposal-level (what to build) → Implementation-level (how to build)

**Impact:**
- No intermediate representation between intent and code
- Proposal-level planning (functional scope) conflated with implementation details
- Harder to reason about "what should we build" vs "how should we build it"

**What OV5 lacks:**
- Explicit proposal-level graph (capabilities, modules)
- Explicit implementation-level graph (files, interfaces, data flows)
- Separation of concerns between "what" and "how"

---

### Gap 4: No Graph-Guided Localization (vs RPG)

**OV5:** When implementing changes, no structural guidance from graph
**RPG:** Graph traversal in topological order, dependencies precede dependents

**Impact:**
- No explicit data flow tracking between modules
- No topological ordering of file/function dependencies
- Localization (where to make changes) is ad-hoc, not graph-guided

**What OV5 lacks:**
- Graph representation of repository structure
- Topological ordering for implementation
- Structural guidance when navigating codebase

---

### Gap 5: No Plan-Level Search (vs PlanSearch)

**OV5:** Searches over backends/models (routing), not over plans
**PlanSearch:** Searches over diverse plans in natural language space

**Impact:**
- No explore-exploit over plan space
- No mechanism to generate multiple candidate plans and select best
- Plan diversity not explicitly optimized

**What OV5 lacks:**
- Plan generation: multiple candidate approaches per target
- Plan diversity metric: how different are the plans?
- Plan selection: choose best plan before implementation

---

## What OV5 Could Learn

### From RPG: Structured Planning Representation

**Concrete improvements:**

1. **Experiment dependency graph:**
   - Represent experiments as nodes, dependencies as edges
   - Topological ordering: prerequisite experiments first
   - Explicit data flow: what does experiment A produce that experiment B consumes?

2. **Two-level experiment planning:**
   - Proposal-level: what capabilities should we improve? (ontology gaps)
   - Implementation-level: how should we implement the improvement? (specific changes)
   - Separate "what" from "how" in hypothesis generation

3. **Graph-guided implementation:**
   - When implementing multi-file changes, use structural graph
   - Topological order: dependencies first, then dependents
   - Explicit interface contracts between modules

---

### From PlanSearch: Diversity-Aware Plan Search

**Concrete improvements:**

1. **Observations → Plans → Solutions pipeline:**
   - Before generating hypothesis, generate diverse observations about target
   - From observations, construct multiple candidate plans
   - Search over plans (diversity metric) before implementation

2. **Plan diversity metric:**
   - Measure how different candidate plans are (semantic similarity)
   - Explicitly maximize diversity to avoid repeated sampling
   - Predict performance gains as function of plan diversity

3. **Plan-level explore-exploit:**
   - Exploit: generate plans similar to successful past plans
   - Explore: generate plans in unexplored regions of plan space
   - Balance via explore-exploit strategy (like RPG's subtree selection)

---

### Combined: Structured Plan Search

**Synthesis of RPG + PlanSearch for OV5:**

1. **Structured plan representation:**
   - Plans as graphs (not free-form NL)
   - Nodes = capabilities/files/functions
   - Edges = data flows/dependencies

2. **Diversity-aware plan generation:**
   - Generate multiple candidate plan graphs
   - Measure diversity via graph similarity
   - Select diverse subset for implementation

3. **Graph-guided plan execution:**
   - Topological ordering of plan nodes
   - Dependencies precede dependents
   - Structural guidance during implementation

---

## Implementation Roadmap (Hypothetical)

### Phase 1: Experiment Dependency Graph (from RPG)

**What:** Represent experiments as graph, not isolated units
**How:**
- Add `experiment-graph.el` module
- Nodes = experiments, edges = dependencies
- Topological sort before execution
- Track data flow between experiments

**Impact:** Enables multi-step experiments with explicit prerequisites

---

### Phase 2: Plan Diversity Metric (from PlanSearch)

**What:** Measure and maximize plan diversity
**How:**
- Add `plan-diversity.el` module
- Generate N candidate plans per target
- Compute pairwise similarity (semantic embedding or structural)
- Select diverse subset (maximize diversity metric)

**Impact:** Avoids repeated sampling of similar approaches

---

### Phase 3: Two-Level Planning (from RPG)

**What:** Separate proposal-level from implementation-level planning
**How:**
- Add `proposal-graph.el` module
- Proposal-level: capabilities, modules (what to build)
- Implementation-level: files, interfaces, data flows (how to build)
- Explicit mapping between levels

**Impact:** Clearer separation of "what" vs "how", reduces plan drift

---

### Phase 4: Graph-Guided Implementation (from RPG)

**What:** Use structural graph when implementing changes
**How:**
- Add `implementation-graph.el` module
- Represent repository structure as graph
- Topological ordering for multi-file changes
- Structural guidance during code generation

**Impact:** More coherent multi-file changes, explicit dependency tracking

---

## Key Takeaways

1. **Structured representation > free-form NL** for long-horizon planning (RPG)
2. **Diversity-aware search > repeated sampling** for code generation (PlanSearch)
3. **Two-level planning** separates "what" from "how" (RPG)
4. **Graph-guided localization** improves implementation coherence (RPG)
5. **Plan-level search** explores more diverse solution space (PlanSearch)

**OV5's gap:** No structured planning representation, no diversity-aware search, no two-level planning, no graph-guided localization.

**Opportunity:** Combine RPG's structured graphs with PlanSearch's diversity-aware search to create a more powerful planning system for OV5.

---

## References

- RPG: arXiv:2509.16198 (Microsoft, Sep 2025)
- PlanSearch: arXiv:2409.03733 (Scale AI, Sep 2024)
- OV5 architecture: OUROBOROS-V5.md
