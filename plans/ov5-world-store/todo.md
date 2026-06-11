---
type: planning
entity: todo
plan: "ov5-world-store"
updated: "2026-06-11"
---

# Todo: OV5 World Store

> Tracking [OV5 World Store](plan.md)

## Active Phase: 2 - TSV Migration

### Phase Context

- **Scope**: [Phase 2](phases/phase-2.md)
- **Implementation**: Phase 2 Plan (to be authored)
- **Latest Handover**: [Session 2026-06-11](handovers/session-2026-06-11.md)
- **Relevant Docs**:
  - `mementum/state.md` — current system state
  - `clj/ov5/world_store.clj` — core namespace
  - `lisp/modules/gptel-ext-world-store.el` — Elisp bridge

### Pending

- [ ] Parse all TSV files in `var/tmp/experiments/2026-*/`
- [ ] Handle 5 schema versions (14, 20, 24, 27, 32 columns)
- [ ] Map TSV columns to Datahike schema attributes
- [ ] Write migration namespace `clj/ov5/world_store/migration.clj`
- [ ] Write Elisp entry point `gptel-ext-world-store-migration.el`
- [ ] Validate: row count match, sample verification
- [ ] Make migration idempotent (upsert by experiment-id)
- [ ] Log schema version distribution and unmappable fields
- [ ] Write migration tests

### In Progress

- [ ] Phase 1 complete — moving to Phase 2

### Completed

- [x] Phase 1: Bootstrap
  - [x] Research Datahike babashka compatibility → use pod v0.8.1697
  - [x] Create `bb.edn` with Datahike pod
  - [x] Write `clj/ov5/world_store.clj` — core namespace (schema, CRUD, query helpers)
  - [x] Write `lisp/modules/gptel-ext-world-store.el` — Elisp bridge
  - [x] Write `tests/test-world-store-bootstrap.el` — 8 tests, all green
  - [x] Verify brepl can load and eval Datahike code
  - [x] Define schema for experiment, backend, strategy, target
  - [x] Test round-trip CRUD via brepl and Elisp
  - [x] Byte-compile Elisp module

### Blocked

- (none)

## Changelog

### 2026-06-11

- Phase 1 COMPLETE: Datahike pod working via babashka brepl; schema defined; CRUD + query helpers functional; Elisp bridge connects/transacts/queries/looks-up entities; 8 bootstrap tests pass
- Phase 2 identified as next: TSV migration from `var/tmp/experiments/2026-*/`
