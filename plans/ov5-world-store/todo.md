---
type: planning
entity: todo
plan: "ov5-world-store"
updated: "2026-06-12"
---

# Todo: OV5 World Store

> Tracking [OV5 World Store](plan.md)

## Plan Completed

OV5 World Store Phase 5 is complete; the branching implementation is verified and the full unit suite is green.

### Phase Context

- **Scope**: [Phase 5](phases/phase-5.md)
- **Implementation**: [Phase 5 Plan](implementation/phase-5-impl.md) (completed)
- **Latest Handover**: [Session 2026-06-11](handovers/session-2026-06-11.md)
- **Relevant Docs**:
  - `mementum/state.md` — current system state
  - `clj/ov5/world_store.clj` — core namespace
  - `clj/ov5/world_store/branch.clj` — branch namespace
  - `lisp/modules/gptel-ext-world-store.el` — Elisp bridge / persistent query path
  - `lisp/modules/gptel-ext-world-store-branch.el` — Elisp branch bridge
  - `lisp/modules/gptel-tools-agent-worktree.el` — worktree utilities
  - `lisp/modules/gptel-tools-agent-experiment-loop.el` — experiment loop workflow
  - `lisp/modules/gptel-tools-agent-staging-merge.el` — staging merge workflow
  - `lisp/modules/gptel-tools-agent-experiment-core.el` — experiment orchestration core
  - `tests/test-world-store-branch.el` — branch tests

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
- [x] Phase 4: Query Layer (implementation + tests)
  - [x] Real Datalog query namespace
  - [x] Elisp query bridge with caching/fallback
  - [x] Hot-path rewrites in ontology-router + ontology-predict
  - [x] 46 relevant tests passing (30 brepl + 8 bootstrap + 8 query)
  - [x] Benchmark sample measured (10k experiments after persistent nREPL bridge: uncached ~67.87ms/query, cached ~0.0117ms/query)
  - [x] Repo-wide unit suite verified (2983 tests, 0 unexpected)
- [x] Phase 5 implementation plan drafted
- [x] Phase 5: Branching
  - [x] Branch create/switch/merge/promote/list/delete
  - [x] Worktree / experiment / staging integration
  - [x] Branch tests
  - [x] Full unit suite verified (2993 tests, 0 unexpected)

## Changelog

### 2026-06-12

- Phase 3 COMPLETE: Context unification working; schema extended with context/approval/risk attributes; plist→map conversion handles single and multiple plists; 3 context tests pass
- Phase 4 identified as next: Query Layer — replace parse-all-results with Datalog queries
- Phase 4 query-layer implementation landed: real query namespace, cache/load-order/fallback fixes, hot-path rewrites, and 16 world-store tests passing; benchmark verification still pending
- Phase 4 persistent bridge verified: `lisp/modules/gptel-ext-world-store.el` now uses a persistent nREPL client for world-store evals; benchmark on 1000 experiments is now ~60.93ms uncached / ~0.0769ms cached; full unit-suite verification still aborts in the current workspace
- Phase 4 completed: 10k benchmark now ~67.87ms uncached / ~0.0117ms cached, repo-wide unit suite passes (2983 tests, 0 unexpected), and Phase 5 branching planning is next
- Phase 5 implementation plan drafted: branching plan now grounded in current worktree workflow; execution pending approval
- Phase 5 completed: branch registry, Elisp bridge, workflow hooks, and tests implemented; full unit suite passes (2993 tests, 0 unexpected). Plan complete.
