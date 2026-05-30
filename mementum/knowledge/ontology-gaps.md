---
title: Ontology Gaps — Theoretical Remaining Work
status: open
category: architecture
tags: [ontology, palantir, gaps, future-work]
related: [project-facts.md, patterns.md]
depends-on: [gptel-auto-workflow-ontology-router.el]
---

# Ontology Gaps — Beyond Incremental Improvement

## Context

The OV5 ontology system was compared against Palantir Ontology
(2026-05-30). Approximately 15 gaps were identified and closed
across 10 categories. The remaining gaps below are **theoretical**
— they would require architectural changes beyond incremental
code improvement.

## Remaining Gaps

### 1. Formal Convergence Proof
**Palantir claims 94% convergence** for their Generate→Validate→Refine
cycle via formal methods. OV5 tracks convergence empirically
(refine-convergence-stats) but has no formal proof.

**Why hard:** Requires model checking, invariant analysis, or
theorem proving — not practical in Emacs Lisp.

**If attempted:** Could instrument the refine loop to emit traces
for external analysis (e.g., TLA+ model checker).

### 2. Full Digital Twin (System State Model)
**Palantir maintains a live synchronized model** of the enterprise
(object properties, relationships, state history). OV5 has a
lightweight `target-state-cache` (byte-compile + syntax only).

**Why hard:** Requires content-aware file analysis (AST parsing,
dependency graph, import resolution). Our `categorize-target`
is filename-regex only.

**If attempted:** Use tree-sitter or Emacs' own semantic analysis
to build a richer file model. Store in the existing digital-twin.json
persistence format.

### 3. Runtime Enforcement for ALL Subagents
**Currently only the executor** has precondition checks
(`check-action-preconditions`). Analyzer, grader, and comparator
bypass the ontology.

**Why hard:** Requires modifying `my/gptel--run-agent-tool-with-timeout`
to accept per-subagent-type schemas. Current dispatch logging
is read-only — the evolution cycle doesn't use it for routing.

**If attempted:** Add `:preconditions` to each subagent type
in `ranked-subagent-backends` or create a subagent-schema
parallel to `category-action-schemas`.

### 4. Auto-Apply Categorization Repair
**`repair-ontology` suggests recategorization** but never applies
it. The `categorize-target` regex patterns never change from
experiment data.

**Why hard:** `categorize-target` uses static `string-match-p`
calls. Updating patterns requires modifying function code or
switching to a data-driven pattern table.

**If attempted:** Replace `categorize-target`'s hardcoded patterns
with the `category-pattern-map` defconst. Add a function
`gptel-auto-workflow--update-category-pattern` that modifies
this defconst at runtime (or its value).

### 5. Postcondition Enforcement for All Paths
**Currently only checked in the refine path.** The main
experiment flow (grade → decide → keep/discard) doesn't
verify commit criteria.

**Why hard:** The experiment result is known after grading
but before committing. Postconditions could be checked at
the decision point in `gptel-auto-experiment-decide`.

**If attempted:** Add postcondition check in `experiment-core.el`
at the `(if passed ...)` branch — before the decide step.

### 6. Unified Routing Path
**Two separate routing paths:** `reorder-fallbacks-by-ontology`
(for executor fallback chain) and `ranked-subagent-backends`
(for subagent dispatch). They use different scoring.

**Why hard:** They serve different purposes (global fallback
chain vs per-dispatch ranking), but the duplicated logic
drifts over time.

**If attempted:** Extract shared scoring into a helper
function used by both paths.

## Priority Order

If resuming work, address in this order:
1. **Runtime enforcement for all subagents** (gap 3) —
   highest impact, least architectural change.
2. **Postcondition enforcement for all paths** (gap 5) —
   follows same pattern as existing refine-path check.
3. **Auto-apply categorization repair** (gap 4) —
   data-driven patterns exist but are not used.
4. **Unified routing path** (gap 6) — cleanup.
5. **Full digital twin** (gap 2) — requires new dependencies.
6. **Formal convergence proof** (gap 1) — research project.

## Source Files

- `lisp/modules/gptel-auto-workflow-ontology-router.el` (3200+ lines)
- `lisp/modules/gptel-tools-agent-experiment-core.el`
- `lisp/modules/gptel-tools-agent-prompt-build.el`
- `lisp/modules/gptel-tools-agent-subagent.el`
