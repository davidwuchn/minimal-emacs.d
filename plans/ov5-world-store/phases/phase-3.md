---
type: planning
entity: phase
plan: "ov5-world-store"
phase: 3
status: pending
created: "2026-06-11"
updated: "2026-06-11"
---

# Phase 3: Context Unification

> Part of [OV5 World Store](../plan.md)

## Objective

Merge fragmented context data (.sexp sidecars, approval history, risk patterns) into unified experiment entities in the World Store. Eliminate the split between metrics (TSV) and narrative (sidecars).

## Scope

### Includes

- Extend schema: context, approval, risk entities linked to experiments
- Parse `var/context/*.sexp` files and link to experiment entities
- Parse `var/approval-history.sexp` and link decisions to experiments
- Parse `var/risk-patterns.sexp` and link to targets
- Write unified entity lookup: `(ws/entity experiment-id)` returns experiment + context + approval + risk
- Update migration to include context data (Phase 2 migration re-runnable)
- Add query helpers: `experiments-by-risk`, `experiments-by-approval-type`

### Excludes (deferred to later phases)

- Real-time context capture (new experiments still write .sexp)
- Mementum markdown files (out of scope per plan)
- Ontology graph unification (Phase 4)

## Prerequisites

- [x] Phase 2 complete — TSV migration done
- [ ] All .sexp files accessible and parseable

## Deliverables

- [ ] Schema extended with context/approval/risk attributes
- [ ] `clj/ov5/world_store/context.clj` — context unification namespace
- [ ] `lisp/modules/gptel-ext-world-store-context.el` — Elisp bridge
- [ ] `tests/test-world-store-context.el` — context tests
- [ ] Unified entity query working end-to-end

## Acceptance Criteria

- [ ] `(ws/entity "exp-123")` returns experiment with linked context, approval, risk
- [ ] All .sexp sidecars transacted and linked
- [ ] All approval history transacted and linked
- [ ] All risk patterns transacted and linked
- [ ] Query `experiments-by-risk` returns correct results
- [ ] Query `experiments-by-approval-type` returns correct results
- [ ] Full test suite still passes (2945 tests, 0 unexpected)

## Dependencies on Other Phases

| Phase | Relationship | Notes |
|-------|-------------|-------|
| 1 | blocked-by | Needs schema |
| 2 | blocked-by | Needs experiment entities to link to |

## Notes

- Context sidecars are linked by experiment-id (may be numeric or string)
- Approval history uses a different ID format; may need fuzzy matching
- Risk patterns are per-target, not per-experiment — link via target attribute
- Some .sexp files may be malformed; handle gracefully with logging
