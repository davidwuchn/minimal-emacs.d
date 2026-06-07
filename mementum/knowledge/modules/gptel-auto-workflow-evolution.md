# gptel-auto-workflow-evolution

## Purpose

The self-evolution engine that drives the Ouroboros V5 system. It runs experiments against target modules, evaluates results via Eight Keys benchmark scoring, and uses mementum as the single source of truth for prompt injection. The engine synthesizes research knowledge, evolves skills, performs VSM health checks, and manages the full evolution cycle — detecting convergence plateaus, gating strategies, and applying Wu Xing diagnostics to repair subsystem imbalances.

## File Stats

- **Lines**: 7762
- **Path**: `lisp/modules/gptel-auto-workflow-evolution.el`

## Key Functions

- `gptel-auto-workflow--memory-status` (L66) — Reports status of all four memory layers (short-term, long-term, structured, temporal).
- `gptel-auto-workflow--eight-keys-convergence-score` (L110) — Computes aggregate Eight Keys score across autogo, autotts, and self-evolve subsystems.
- `gptel-auto-workflow--parse-all-results` (L225) — Parses all experiment TSV results, optionally filtered by age.
- `gptel-auto-workflow--git-raw-facts` (L413) — Extracts raw git facts (commits, diffs, log) for evolution input.
- `gptel-auto-workflow--synthesize-causal-chains` (L517) — Builds causal chains from experiment results using knowledge reasoning.
- `gptel-auto-workflow--synthesize-gap-detection` (L543) — Detects gaps in knowledge coverage using Allen's interval algebra.
- `gptel-auto-workflow--gap-prioritize-targets` (L582) — Prioritizes targets by gap size for next experiment cycle.
- `gptel-auto-workflow--evolution-synthesize` (L617) — Core synthesis: merges experiment results with mementum knowledge.
- `gptel-auto-workflow--evolution-get-knowledge` (L861) — Retrieves synthesized knowledge for prompt injection.
- `gptel-auto-workflow--evolution-consolidate-insights` (L895) — Consolidates experiment insights into persistent knowledge.
- `gptel-auto-workflow--evolve-all-skills` (L2060) — Evolves all research skills based on experiment outcomes.
- `gptel-auto-workflow-evolution-run-cycle` (L2092) — Main entry: runs a full evolution cycle (analyze → synthesize → evolve → gate).
- `gptel-auto-workflow--evolution-vsm-health-check` (L2589) — Wu Xing VSM diagnostic that detects and repairs subsystem imbalances.
- `gptel-auto-workflow--detect-minimal-pairs` (L2809) — Finds minimal experiment pairs that differ by one variable.
- `gptel-auto-workflow--gate-strategies` (L3715) — Gates strategies based on keep rate, champion scores, and category budgets.
- `gptel-auto-workflow--detect-overfitting` (L3860) — Evaluates holdout set to detect overfitted strategies.
- `gptel-auto-workflow--second-chance-repair` (L4145) — Attempts to repair aborted experiments for a second evaluation.

## Dependencies

- `cl-lib`, `json`, `seq`, `subr-x`
- `gptel-auto-workflow-research-integration` (soft)
- `gptel-auto-workflow-research-benchmark` (soft)
- `gptel-auto-workflow-knowledge-reasoning` (soft)

## Integration Points

- **gptel-tools-agent-base** — worktree base root, git operations, read file contents
- **gptel-auto-workflow-knowledge-reasoning** — causal analysis, gap detection, ontology consistency
- **gptel-tools-agent-prompt-build** — skill loading, allium distillation, prompt compilation
- **gptel-tools-agent-main** — `run-async` for queuing experiments
- **gptel-benchmark-principles** — Eight Keys scoring for convergence and champion selection
- **gptel-auto-workflow-research-benchmark** — research trace loading and evolution
- **gptel-auto-workflow-ontology-router** — JSON encoding of plist data

## See Also

- [gptel-auto-workflow-production](gptel-auto-workflow-production.md) — Production timer and hook integration
- [gptel-auto-workflow-strategic](gptel-auto-workflow-strategic.md) — Target selection feeding into evolution
- [gptel-auto-workflow-knowledge-reasoning](gptel-auto-workflow-knowledge-reasoning.md) — Causal reasoning engine
- [gptel-auto-workflow-bootstrap](gptel-auto-workflow-bootstrap.md) — Headless bootstrap for daemon

---
*Auto-generated from code header. Manually refined 2026-06-06.*