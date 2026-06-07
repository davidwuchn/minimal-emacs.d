---
type: planning
entity: phase
plan: "monitoring-agent"
phase: 2
status: pending
created: "2026-06-06"
updated: "2026-06-06"
---

# Phase 2: Proposal Generation

> Part of [Monitoring Agent](../plan.md)

## Objective

Generate improvement proposals for systemic failures detected in Phase 1. The agent should analyze failure patterns and produce specific, testable fixes.

## Scope

### Includes

- Read failure patterns from mementum
- Generate improvement proposals (code changes, prompt adjustments, strategy fixes)
- Score proposals by estimated impact and feasibility
- Validate proposals against historical data
- Persist proposals to mementum

### Excludes (deferred to later phases)

- Auto-deployment
- Live testing against running pipeline

## Prerequisites

- [ ] Phase 1 complete (failure patterns detected)
- [ ] Access to component code (grader, prompt builder, strategy harness)
- [ ] Historical experiment data for validation

## Deliverables

- [ ] `gptel-auto-workflow--generate-improvement-proposal` function
- [ ] `gptel-auto-workflow--score-proposal` function
- [ ] `gptel-auto-workflow--validate-proposal` function
- [ ] Unit tests for proposal generation
- [ ] Memory: `mementum/memories/monitoring-agent-proposals.md`

## Acceptance Criteria

- [ ] Generates 1+ proposal per week for systemic failures
- [ ] Proposals are specific (not generic advice)
- [ ] Score proposals by estimated impact and feasibility
- [ ] Validate against historical data
- [ ] Persist to mementum

## Dependencies on Other Phases

| Phase | Relationship | Notes |
|-------|-------------|-------|
| Phase 1 | blocks | Phase 1 must complete first |
| Phase 3 | blocked-by | Phase 2 must complete before deployment |

## Notes

- Proposal types:
  - **Grader fix**: Rewrite grader function, add new grader rule
  - **Prompt fix**: Adjust prompt template, add context
  - **Strategy fix**: Change strategy selection logic
  - **Target fix**: Adjust target prioritization

- Proposal format:
  ```elisp
  '(:description "Rewrite grader to handle X"
    :component "grader"
    :code-changes "..."
    :expected-impact "Reduce failures by 30%"
    :confidence 0.8
    :risk "low")
  ```
