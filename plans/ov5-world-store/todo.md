---
type: planning
entity: todo
plan: "ov5-world-store"
updated: "2026-06-11"
---

# Todo: OV5 World Store

> Tracking [OV5 World Store](plan.md)

## Active Phase: 1 - Bootstrap

### Phase Context

- **Scope**: [Phase 1](phases/phase-1.md)
- **Implementation**: [Phase 1 Plan](implementation/phase-1-impl.md)
- **Latest Handover**: [Session 2026-06-11](handovers/session-2026-06-11.md)
- **Relevant Docs**:
  - `mementum/state.md` — current system state
  - `.opencode/skills/brepl/SKILL.md` — brepl usage
  - `lisp/modules/gptel-ext-brepl.el` — brepl Elisp module

### Pending

- [ ] Research Datahike babashka compatibility (pod vs deps.edn)
- [ ] Create `bb.edn` or `deps.edn` with Datahike
- [ ] Write `clj/ov5/world_store.clj` — core namespace
- [ ] Write `lisp/modules/gptel-ext-world-store.el` — Elisp bridge
- [ ] Write `tests/test-world-store-bootstrap.el` — tests
- [ ] Verify brepl can load and eval Datahike code
- [ ] Define schema for experiment, backend, strategy, target
- [ ] Test round-trip CRUD via brepl
- [ ] Test round-trip CRUD via Elisp
- [ ] Byte-compile Elisp module

### In Progress

- [ ] Plan created and reviewed

### Completed

- [x] Plan created for OV5 World Store

### Blocked

- [ ] Datahike installation — blocked until babashka compatibility confirmed

## Changelog

### 2026-06-11

- Plan created with 5 phases: Bootstrap, TSV Migration, Context Unification, Query Layer, Branching
- Phase 1 (Bootstrap) identified as active; Datahike compatibility research is first task
