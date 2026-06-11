---
type: planning
entity: phase
plan: "ov5-world-store"
phase: 5
status: completed
created: "2026-06-11"
updated: "2026-06-12"
---

# Phase 5: Branching

> Part of [OV5 World Store](../plan.md)

## Objective

Implement branchable stores for isolated experiments. Each experiment run can create a branch, write results without affecting main, and promote successful results.

## Scope

### Includes

- Design branch model: branch = Datahike database with parent reference
- Implement branch operations:
  - `create-branch` — new branch from main (or from parent branch)
  - `switch-branch` — change active branch
  - `merge-branch` — merge branch into main (or parent)
  - `promote-branch` — promote branch to become new main
  - `list-branches` — show all branches
  - `delete-branch` — remove branch
- Integrate with OV5 worktree workflow:
  - Experiment worktree → auto-create branch
  - Staging merge → merge branch into main
  - Promotion → promote branch to main
- Add branch metadata: created-at, parent, experiment-run-id, status
- Tests: branch isolation, merge correctness, promotion safety

### Excludes (deferred to later phases)

- Concurrent branch writes (single-writer assumption)
- Branch-level access control
- Remote/sync branches across machines

## Prerequisites

- [x] Phase 4 complete — query layer working
- [x] Understanding of OV5 worktree workflow (staging-merge, experiment-loop)

## Deliverables

- [x] `clj/ov5/world_store/branch.clj` — branching namespace
- [x] `lisp/modules/gptel-ext-world-store-branch.el` — Elisp branch bridge
- [x] Integration with `gptel-tools-agent-staging-merge.el`
- [x] Integration with `gptel-tools-agent-experiment-loop.el`
- [x] `tests/test-world-store-branch.el` — branching tests

## Acceptance Criteria

- [x] Can create branch, write experiment, query returns data
- [x] Main store unchanged after branch write
- [x] Merge branch into main: main now has branch data
- [x] Promotion: branch becomes new main, old main preserved
- [x] Worktree experiment auto-creates branch on start
- [x] Staging merge merges branch into main
- [x] Full test suite still passes (2993 tests, 0 unexpected)

## Dependencies on Other Phases

| Phase | Relationship | Notes |
|-------|-------------|-------|
| 1 | blocked-by | Needs store |
| 4 | blocked-by | Needs query layer for branch queries |

## Notes

- Datahike's `d/datafy` or separate database files per branch
- Simplest approach: separate Datahike database per branch, merge via transaction replay
- Branch names: `main`, `optimize-<target>-<timestamp>`, `experiment-<id>`
- Promotion should be atomic: rename main → main-@timestamp, promote branch → main
- Keep branch history for audit trail
- Phase 5 implemented and verified; branch registry + integration hooks are complete.
