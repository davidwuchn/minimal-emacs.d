---
title: Follow Existing Naming Conventions — No ov5- Prefixes
φ: 0.85
e: naming-conventions-follow-existing
λ: when.creating.new.modules
Δ: 0.05
evidence: 1
sources:
  - ls lisp/modules/
---

💡 The codebase already has established naming conventions. Do not invent new prefixes.

## Existing Conventions

| Prefix | Used For | Examples |
|--------|----------|----------|
| `gptel-auto-workflow-*.el` | Core workflow systems | `gptel-auto-workflow-evolution.el`, `gptel-auto-workflow-ontology-router.el` |
| `gptel-tools-agent-*.el` | Agent tools and subagents | `gptel-tools-agent-experiment-core.el`, `gptel-tools-agent-prompt-build.el` |
| `skill-*.el` | Skill-specific modules | `skill-routing-onto.el` |
| `gptel-benchmark-*.el` | Benchmarking | `gptel-benchmark-principles.el`, `gptel-benchmark-subagent.el` |

## What NOT to Do

- ❌ `ov5-skill-graph.el` — invented prefix, breaks convention
- ❌ `ov5-sg--*` functions — inconsistent with codebase style

## What TO Do

- ✅ `gptel-auto-workflow-skill-graph.el` — follows existing `gptel-auto-workflow-*` pattern
- ✅ `gptel-auto-workflow-skill-evolve.el` — fits into evolution cycle
- ✅ Extend `skill-routing-onto.el` — add graph dimensions to existing router
- ✅ Hook into `gptel-auto-workflow-evolution.el` — hourly cron already lives there

## Decision

New skill graph functionality should be:
1. Data structures + executor: `gptel-auto-workflow-skill-graph.el`
2. Evolution logic: hook into existing `gptel-auto-workflow-evolution.el`
3. Router dimensions: extend `skill-routing-onto.el`
4. Tests: `test-gptel-auto-workflow-skill-graph.el`
