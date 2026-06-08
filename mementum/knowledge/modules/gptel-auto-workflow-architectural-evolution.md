---
title: Architectural Evolution
status: active
category: auto-workflow
tags: [yc, auto-workflow, architecture, strategy-routing, hypothesis-routing, monitoring-agent-phase-4]
related: [gptel-auto-workflow-monitoring-agent, gptel-auto-workflow-evolution, gptel-auto-workflow-mementum]
---

# Architectural Evolution

> Structural pipeline proposals from experiment data. Analyzes strategy routing effectiveness, hypothesis category routing, and generates architectural proposals with risk classification for the monitoring agent's Phase 4.

## Purpose

Architectural evolution extends the monitoring agent with higher-level pattern analysis beyond individual failure patterns. It analyzes experiment records to detect systemic strategic issues: which research strategies are underperforming (below 40% keep-rate), which hypothesis categories are routed to wrong strategies, and whether structural changes (module add/remove/split) are needed. It generates architectural proposals with risk classification (`investigation` → auto-deploy, `routing-change` → notify, `module-remove/add/split` → approval-required) and adds legacy keys (`:confidence`, `:risk`, `:component`) so the monitoring agent's `--score-proposal` can process them. Results are persisted to mementum as `💡` memories.

## Public Functions

| Function | Purpose |
|----------|---------|
| `gptel-auto-workflow--architectural-risk-classify` | Classify a `change-type` symbol into risk level string (low/medium/high) |
| `gptel-auto-workflow--architectural-risk->deploy-action` | Map risk string to deployment action (auto-deploy/notify/approval-required) |
| `gptel-auto-workflow--analyze-strategy-routing` | Group experiments by `:research-strategy`, compute kept-rate per strategy; return sorted worst-first |
| `gptel-auto-workflow--analyze-hypothesis-routing` | Group by hypothesis category + strategy, compute kept-rate; classify change-type for each combination |
| `gptel-auto-workflow--generate-architectural-proposal` | Generate a proposal plist from a routing group with legacy keys for scoring compatibility |
| `gptel-auto-workflow--architectural-proposal->string` | Format a proposal plist into a human-readable mementum string |
| `gptel-auto-workflow--architectural-slug` | Generate a mementum slug for architectural proposals |
| `gptel-auto-workflow--run-architectural-analysis` | Entry point: load records, run Phase A (strategy routing) + Phase B (hypothesis routing), score + persist all proposals |

## Key Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `gptel-auto-workflow-architectural-min-occurrences` | `3` | Minimum occurrences of a routing pattern before proposing changes |
| `gptel-auto-workflow-architectural-routing-success-threshold` | `0.4` | Keep-rate threshold below which a strategy is considered ineffective |

## Integration Points

- **Monitoring Agent (Phase 4)**: Called via `gptel-auto-workflow--run-architectural-analysis` from the monitoring cycle's Phase 4 step. Architectural proposals are persisted alongside failure-pattern proposals.
- **Evolution Module**: Uses `gptel-auto-workflow--parse-all-results` (via `declare-function` + `fboundp` guard) to load experiment records. Uses `gptel-auto-workflow--categorize-hypothesis` for hypothesis category routing analysis.
- **Monitoring Agent Scoring**: Generates proposals with legacy keys (`:confidence`, `:risk`, `:component`) so `gptel-auto-workflow--score-proposal` can process them.
- **Mementum**: Writes `💡` memories for each architectural proposal via `gptel-auto-workflow--mementum-write-memory`.

## Test Coverage

No dedicated test file found. Tested implicitly through the monitoring agent's Phase 4 execution.