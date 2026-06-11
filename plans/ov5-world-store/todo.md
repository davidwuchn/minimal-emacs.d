---
type: planning
entity: todo
plan: "ov5-world-store"
updated: "2026-06-11"
---

# Todo: OV5 World Store

> Tracking [OV5 World Store](plan.md)

## Active Phase: 3 - Context Unification

### Phase Context

- **Scope**: [Phase 3](phases/phase-3.md)
- **Implementation**: Phase 3 Plan (to be authored)
- **Latest Handover**: [Session 2026-06-11](handovers/session-2026-06-11.md)
- **Relevant Docs**:
  - `mementum/state.md` — current system state
  - `clj/ov5/world_store.clj` — core namespace
  - `clj/ov5/world_store/migration.clj` — migration namespace
  - `lisp/modules/gptel-ext-world-store.el` — Elisp bridge

### Pending

- [ ] Parse `var/context/*.sexp` files and link to experiment entities
- [ ] Parse `var/approval-history.sexp` and link decisions to experiments
- [ ] Parse `var/risk-patterns.sexp` and link to targets
- [ ] Write unified entity lookup
- [ ] Add context attributes to schema
- [ ] Write context unification namespace
- [ ] Write tests for context unification

### In Progress

- [ ] Phase 2 complete — moving to Phase 3

### Completed

- [x] Phase 1: Bootstrap
  - [x] Datahike pod via babashka brepl
  - [x] Schema defined (experiment/backend/strategy/target)
  - [x] CRUD + query helpers
  - [x] Elisp bridge
  - [x] 8 bootstrap tests
- [x] Phase 2: TSV Migration
  - [x] 3 schema versions (30/39/43 columns)
  - [x] Type coercion (double/long/keyword/string)
  - [x] Run-ID namespacing for unique IDs
  - [x] Deterministic UUID from path
  - [x] 105 files → 124 rows → 87 experiments migrated
  - [x] 3 migration tests (single, multi-schema, idempotent)

### Blocked

- (none)

## Changelog

### 2026-06-11

- Phase 2 COMPLETE: TSV migration working; 87 experiments in World Store
- Phase 3 identified as next: Context unification (.sexp sidecars, approval, risk)
