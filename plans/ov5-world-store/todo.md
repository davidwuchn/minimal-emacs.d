---
type: planning
entity: todo
plan: "ov5-world-store"
updated: "2026-06-11"
---

# Todo: OV5 World Store

> Tracking [OV5 World Store](plan.md)

## Active Phase: 4 - Query Layer

### Phase Context

- **Scope**: [Phase 4](phases/phase-4.md)
- **Implementation**: Phase 4 Plan (to be authored)
- **Latest Handover**: [Session 2026-06-11](handovers/session-2026-06-11.md)
- **Relevant Docs**:
  - `mementum/state.md` — current system state
  - `clj/ov5/world_store.clj` — core namespace
  - `clj/ov5/world_store/migration.clj` — migration namespace
  - `clj/ov5/world_store/context.clj` — context unification namespace
  - `lisp/modules/gptel-ext-world-store.el` — Elisp bridge

### Pending

- [ ] Profile all `parse-all-results` call sites
- [ ] Write Datalog query equivalents for each usage pattern
- [ ] Add query helpers (experiments-by-target/backend/strategy/decision)
- [ ] Add metrics helpers (backend-keep-rate, strategy-keep-rate, etc.)
- [ ] Update Elisp modules to use query layer
- [ ] Add caching layer for expensive queries
- [ ] Benchmark query latency vs TSV parsing
- [ ] Write query layer tests

### In Progress

- [ ] Phase 3 complete — moving to Phase 4

### Completed

- [x] Phase 1: Bootstrap
  - [x] Datahike pod via babashka brepl
  - [x] Schema defined (experiment/backend/strategy/target)
  - [x] CRUD + query helpers
  - [x] Elisp bridge
  - [x] 8 bootstrap tests
- [x] Phase 2: TSV Migration
  - [x] 3 schema versions (30/39/43 columns)
  - [x] 105 files → 124 rows → 87 experiments migrated
  - [x] 3 migration tests
- [x] Phase 3: Context Unification
  - [x] Schema extensions for context/approval/risk
  - [x] Plist→map conversion for EDN parsing
  - [x] Context sidecar unification (by target)
  - [x] Approval history unification (by target)
  - [x] Risk pattern unification (by target)
  - [x] 3 context tests

### Blocked

- (none)

## Changelog

### 2026-06-11

- Phase 3 COMPLETE: Context unification working; schema extended with context/approval/risk attributes; plist→map conversion handles single and multiple plists; 3 context tests pass
- Phase 4 identified as next: Query Layer — replace parse-all-results with Datalog queries
