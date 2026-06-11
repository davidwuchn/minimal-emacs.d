---
type: planning
entity: phase
plan: "ov5-world-store"
phase: 1
status: pending
created: "2026-06-11"
updated: "2026-06-11"
---

# Phase 1: Bootstrap

> Part of [OV5 World Store](../plan.md)

## Objective

Install Datahike, define the core schema, and establish basic CRUD operations accessible from the existing brepl (Clojure REPL). Create the foundation that all subsequent phases build on.

## Scope

### Includes

- Create `bb.edn` with Datahike dependency (or deps.edn if babashka pod insufficient)
- Install/start Datahike via brepl
- Define schema for core entities: experiment, backend, strategy, target
- Write Clojure namespace `ov5.world-store` with:
  - `connect` — create/open database
  - `transact` — add/update entities
  - `query` — Datalog query wrapper
  - `entity` — lookup by ID
- Write Elisp bridge module `gptel-ext-world-store.el`:
  - `ov5-world-store-connect` — start Datahike via brepl
  - `ov5-world-store-transact` — send transaction from Elisp
  - `ov5-world-store-query` — send Datalog query from Elisp
  - `ov5-world-store-entity` — lookup entity from Elisp
- Tests: connection, schema validation, round-trip CRUD

### Excludes (deferred to later phases)

- TSV migration (Phase 2)
- Context unification (Phase 3)
- Query optimization (Phase 4)
- Branching (Phase 5)
- Full schema (task, memory, context entities deferred)

## Prerequisites

- [x] brepl skill installed and working
- [x] babashka available at `~/.local/bin/brepl`
- [ ] Datahike dependency resolved (bb.edn or deps.edn)

## Deliverables

- [ ] `bb.edn` or `deps.edn` with Datahike
- [ ] `clj/ov5/world_store.clj` — core Clojure namespace
- [ ] `lisp/modules/gptel-ext-world-store.el` — Elisp bridge
- [ ] `tests/test-world-store-bootstrap.el` — bootstrap tests
- [ ] Documentation: setup instructions, schema reference

## Acceptance Criteria

- [ ] `brepl <<'EOF' (require '[ov5.world-store :as ws]) (ws/connect "/tmp/ov5-store") EOF` succeeds
- [ ] Can transact a sample experiment entity and query it back
- [ ] Elisp `(ov5-world-store-connect)` returns truthy
- [ ] Elisp `(ov5-world-store-query '[:find ?e :where [?e :experiment/target "foo.el"]])` returns results
- [ ] All bootstrap tests pass
- [ ] Byte-compiles without errors

## Dependencies on Other Phases

| Phase | Relationship | Notes |
|-------|-------------|-------|
| None | — | Foundation phase; all others depend on this |

## Notes

- Datahike with babashka may require a pod. Research `datahike.pod` or use `deps.edn` + `clj` CLI.
- Store directory: `/tmp/ov5-world-store/` (configurable via `ov5-world-store-directory`)
- Schema should use Datahike's `:db/valueType` and `:db/cardinality` attributes
- Keep schema minimal — only experiment, backend, strategy, target for Phase 1
