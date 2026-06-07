---
type: planning
entity: phase
plan: "monitoring-agent"
phase: 1
status: pending
created: "2026-06-06"
updated: "2026-06-06"
---

# Phase 1: Failure Pattern Analysis

> Part of [Monitoring Agent](../plan.md)

## Objective

Implement the failure pattern detection engine that reads TSV logs, identifies recurring failures, and classifies them by type, component, and target. This is the "sensor" layer of the monitoring agent.

## Scope

### Includes

- Parse historical `results.tsv` files (columns 1-32 + production metrics 33-39)
- Detect recurring failures (same grader_reason, same target, same component)
- Classify failures: grader failure, prompt failure, strategy failure, compilation failure
- Track failure frequency, trend, and severity
- Persist patterns to mementum

### Excludes (deferred to later phases)

- Proposal generation
- Auto-deployment
- Historical validation of proposals

## Prerequisites

- [ ] Understanding of TSV schema (columns, types, meanings)
- [ ] Access to historical TSV data
- [ ] Mementum persistence layer available

## Deliverables

- [ ] `gptel-auto-workflow--analyze-systemic-failures` function
- [ ] `gptel-auto-workflow--classify-failure` function
- [ ] `gptel-auto-workflow--failure-pattern->string` function
- [ ] Unit tests for pattern detection
- [ ] Memory: `mementum/memories/monitoring-agent-patterns.md`

## Acceptance Criteria

- [ ] Detects recurring failures with >80% accuracy
- [ ] Classifies failures into 4+ categories
- [ ] Requires 3+ occurrences before flagging as systemic
- [ ] Persists patterns to mementum
- [ ] Throttled to max 1 cycle per 15 minutes

## Dependencies on Other Phases

| Phase | Relationship | Notes |
|-------|-------------|-------|
| Phase 2 | blocked-by | Phase 1 must complete before proposal generation |

## Notes

- Failure classification:
  - **Grader failure**: grader_reason contains "syntax error", "type mismatch", "undefined function"
  - **Prompt failure**: prompt too long, missing context, unclear instructions
  - **Strategy failure**: wrong strategy selected, poor target prioritization
  - **Compilation failure**: code doesn't compile, missing dependencies

- TSV columns of interest:
  - col 1: run_id
  - col 2: timestamp
  - col 3: target
  - col 4: model
  - col 5: strategy
  - col 6: decision (keep/reject)
  - col 7: score_before
  - col 8: score_after
  - col 9: score_delta
  - col 10: grader_reason
  - col 11: ai_comment
  - col 12+: production metrics
