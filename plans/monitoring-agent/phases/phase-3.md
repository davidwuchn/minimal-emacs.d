---
type: planning
entity: phase
plan: "monitoring-agent"
phase: 3
status: pending
created: "2026-06-06"
updated: "2026-06-06"
---

# Phase 3: Auto-Test & Deploy

> Part of [Monitoring Agent](../plan.md)

## Objective

Test proposals against historical data and auto-deploy if they improve the system. Implement safe rollback and human-in-the-loop for high-risk changes.

## Scope

### Includes

- Historical validation: run proposal against past TSV data
- Success rate calculation: did the proposal improve outcomes?
- Auto-deployment if success rate > 60%
- Safe rollback with git worktree isolation
- Human-in-the-loop for high-risk proposals (meta-changes)

### Excludes

- Rewriting external dependencies
- Production monitoring (already implemented)

## Prerequisites

- [ ] Phase 2 complete (proposals generated)
- [ ] Git worktree isolation available
- [ ] Benchmark suite passes

## Deliverables

- [ ] `gptel-auto-workflow--test-proposal` function
- [ ] `gptel-auto-workflow--deploy-proposal` function
- [ ] `gptel-auto-workflow--rollback-proposal` function
- [ ] Integration tests for full cycle
- [ ] Memory: `mementum/memories/monitoring-agent-deployment.md`

## Acceptance Criteria

- [ ] Tests proposals against historical data
- [ ] Auto-deploys if success rate > 60%
- [ ] Safe rollback works
- [ ] Human approval for high-risk proposals
- [ ] All tests pass

## Dependencies on Other Phases

| Phase | Relationship | Notes |
|-------|-------------|-------|
| Phase 2 | blocks | Phase 2 must complete first |

## Notes

- Deployment flow:
  1. Test proposal against historical data
  2. Calculate success rate
  3. If > 60%: deploy to staging
  4. Run benchmark suite
  5. If passes: deploy to main
  6. If fails: rollback

- Rollback strategy:
  - Keep previous version in git worktree
  - Tag previous version
  - Rollback on failure

- Human-in-the-loop:
  - Low risk: auto-deploy
  - Medium risk: notify human, deploy after 24h if no objection
  - High risk: require human approval
