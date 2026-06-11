---
type: planning
entity: phase
plan: "ov5-world-store"
phase: 4
status: pending
created: "2026-06-11"
updated: "2026-06-11"
---

# Phase 4: Query Layer

> Part of [OV5 World Store](../plan.md)

## Objective

Replace `gptel-auto-workflow--parse-all-results` and other TSV-parsing hot paths with Datalog queries against the World Store. Add query helpers for common routing and analysis patterns.

## Scope

### Includes

- Profile current `parse-all-results` usage — find all call sites
- Write Datalog query equivalents for each usage pattern
- Add Clojure namespace `ov5.world-store.query` with helper functions:
  - `experiments-by-target` — all experiments for a file
  - `experiments-by-backend` — all experiments using a backend
  - `experiments-by-strategy` — all experiments using a strategy
  - `experiments-by-decision` — kept/discarded/timeout/etc.
  - `backend-keep-rate` — keep rate per backend
  - `strategy-keep-rate` — keep rate per strategy
  - `category-keep-rate` — keep rate per target category
  - `recent-experiments` — last N experiments
  - `experiments-by-date-range` — experiments in time window
- Update Elisp modules to use query layer instead of parse-all-results
- Add caching layer for expensive queries (time-bounded)
- Benchmark: query latency vs TSV parsing

### Excludes (deferred to later phases)

- Full ontology graph replacement (unified graph is Phase 5+)
- Complex graph traversals (causal chains, prerequisite edges)
- Real-time query streaming

## Prerequisites

- [x] Phase 3 complete — all data in World Store
- [ ] Understanding of all `parse-all-results` call sites

## Deliverables

- [ ] `clj/ov5/world_store/query.clj` — query namespace
- [ ] `lisp/modules/gptel-ext-world-store-query.el` — Elisp query bridge
- [ ] Updated call sites: ontology-router, ontology-predict, staging-merge, etc.
- [ ] `tests/test-world-store-query.el` — query tests
- [ ] Benchmark report

## Acceptance Criteria

- [ ] `parse-all-results` eliminated from routing hot path (ontology-router, ontology-predict)
- [ ] All query helpers return correct results verified against TSV ground truth
- [ ] Query latency < 100ms for common routing queries (10k experiments)
- [ ] Caching reduces repeated query latency by >50%
- [ ] Full test suite still passes (2945 tests, 0 unexpected)

## Dependencies on Other Phases

| Phase | Relationship | Notes |
|-------|-------------|-------|
| 1 | blocked-by | Needs store |
| 2 | blocked-by | Needs experiment data |
| 3 | blocked-by | Needs context data for some queries |

## Notes

- `parse-all-results` is called from many modules; trace all usages
- Some queries may need composite indices (backend + category + strategy)
- Cache invalidation: clear on transaction, or time-based TTL
- Keep TSV fallback for graceful degradation (configurable)
- Benchmark on actual data (10k+ experiments)
