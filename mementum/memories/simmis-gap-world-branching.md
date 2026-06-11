# Simmis vs OV5: Biggest Gap Is World Branching, Not Code Branching

## Insight
Simmis (simm.is) is a Clojure-based simulation platform with the same meta-belief as OV5: many small tries beat one perfect answer. But Simmis makes **branching alternative worlds cheap** (immutable Datalog, O(1) computation forking, Bayesian posteriors, causal DAGs with do-operator), while OV5 makes **running real code interventions safe** (git worktrees, 7 gates, self-heal, monitoring).

The biggest gap: OV5 can fork the filesystem (git worktrees) but cannot fork the reasoning context (prompts, retrieved memory, router state, intermediate analysis). Simmis can fork both. This means OV5's experiments are isolated at the code level but share state at the reasoning level.

## Actionable takeaway
The recommended architecture move: keep Elisp as control plane (orchestration, gates, git), add Clojure as model plane (Datahike world store, Bayesian posteriors, causal DAGs). The brepl bridge already exists. Build the OV5 World Store as P0.

## Why this matters
OV5's self-evolution is limited by its inability to reason about counterfactuals. Without causal models, it can't distinguish "this experiment failed because the strategy was wrong" from "this experiment failed because the backend was slow." Bayesian posteriors over backend/strategy/target quality would turn heuristic routing into calibrated decision-making.
