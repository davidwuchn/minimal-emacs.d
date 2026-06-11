---
type: planning
entity: phase
plan: "ov5-world-store"
phase: 2
status: pending
created: "2026-06-11"
updated: "2026-06-11"
---

# Phase 2: TSV Migration

> Part of [OV5 World Store](../plan.md)

## Objective

Migrate all existing experiment results from TSV files (`var/tmp/experiments/*/results.tsv`) into the World Store. Handle all 5 TSV schema versions gracefully.

## Scope

### Includes

- Write `ov5.world-store.migration` Clojure namespace
- Parse all TSV files in `var/tmp/experiments/2026-*/`
- Handle 5 schema versions (14, 20, 24, 27, 32 columns)
- Map TSV columns to Datahike schema attributes
- Transact all experiments into World Store
- Validation: row count match, sample verification
- Idempotency: re-running migration is safe (upsert by experiment-id)
- Logging: report per-directory stats, unmappable fields, schema version distribution

### Excludes (deferred to later phases)

- Context sidecars (.sexp) — Phase 3
- Approval history, risk patterns — Phase 3
- Deleting TSV files (keep as audit trail)
- Real-time sync (new experiments still write TSV; batch migration only)

## Prerequisites

- [x] Phase 1 complete — Datahike connected, schema defined
- [ ] All TSV directories accessible and readable

## Deliverables

- [ ] `clj/ov5/world_store/migration.clj` — migration namespace
- [ ] `lisp/modules/gptel-ext-world-store-migration.el` — Elisp entry point
- [ ] `tests/test-world-store-migration.el` — migration tests
- [ ] Migration log/report

## Acceptance Criteria

- [ ] All TSV rows from all `var/tmp/experiments/2026-*/` directories transacted
- [ ] Row count: `(count (ws/query all-experiments))` == sum of all TSV rows
- [ ] Sample verification: 10 random experiments have correct attributes
- [ ] Schema version distribution logged
- [ ] Unmappable fields logged (not silently dropped)
- [ ] Re-running migration is idempotent (no duplicates)
- [ ] All migration tests pass
- [ ] Full test suite still passes (2945 tests, 0 unexpected)

## Dependencies on Other Phases

| Phase | Relationship | Notes |
|-------|-------------|-------|
| 1 | blocked-by | Needs Datahike schema from Phase 1 |

## Notes

- TSV columns vary by version. Detect column count per file.
- Common columns across versions: run_id, target, hypothesis, score_before, score_after, decision
- Use Datahike's `:db.unique/identity` on experiment-id for upserts
- Migration should be resumable — track last-processed directory
- Consider writing a migration status file to `var/tmp/world-store-migration-status.json`
