# Todo: Monitoring Agent

> Part of [Monitoring Agent](plan.md)

## Phase Context

**Current Phase**: Phase 2 — Proposal Generation (Phase 1 COMPLETE)
**Phase Doc**: [Phase 1](phases/phase-1.md) | [Phase 2](phases/phase-2.md)
**Implementation Plan**: Phase 1 complete

## Phase 1 Completed ✅

- [x] **P0** Create `lisp/modules/gptel-auto-workflow-monitoring-agent.el` (241 lines)
- [x] **P0** Implement `gptel-auto-workflow--classify-failure` (5 categories: grader, compilation, prompt, strategy, unknown)
- [x] **P0** Implement `gptel-auto-workflow--analyze-systemic-failures` (groups by type+target, filters ≥3 occurrences)
- [x] **P0** Implement `gptel-auto-workflow--failure-pattern->string` (human-readable format)
- [x] **P0** Implement `gptel-auto-workflow--monitoring-cycle` (throttled, persists to mementum)
- [x] **P0** Unit tests (13 ERT tests, all passing)

## Phase 2 In Progress

- [ ] **P0** Consume failure patterns from mementum
- [ ] **P0** Generate improvement proposals for systemic failures
- [ ] **P0** Score proposals by impact and feasibility
- [ ] **P0** Validate proposals against historical data
- [ ] **P0** Persist proposals to mementum

## Changelog

### 2026-06-06

- Phase 1 implemented and tested
- Module: `lisp/modules/gptel-auto-workflow-monitoring-agent.el`
- Tests: `tests/test-gptel-auto-workflow-monitoring-agent.el` (13 tests)
