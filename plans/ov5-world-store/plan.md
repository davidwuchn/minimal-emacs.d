---
type: planning
entity: plan
plan: "ov5-world-store"
status: draft
created: "2026-06-11"
updated: "2026-06-11"
---

# Plan: OV5 World Store

## Objective

Build a branchable Datahike-backed World Store that unifies OV5's fragmented experiment, task, context, and memory data. Replace TSV/.sexp/JSON ad-hoc storage with a queryable Datalog graph accessible via the existing brepl (Clojure REPL).

## Motivation

Current storage is a fragmented mess:
- **TSV files** (`var/tmp/experiments/*/results.tsv`) — 5 schema versions, re-parsed for every query
- **.sexp sidecars** (`var/context/*.sexp`) — detached from experiment records
- **JSON blobs** (`var/tmp/*.json`) — ephemeral, rebuilt hourly
- **In-memory hash tables** — lost on restart

Every routing decision re-parses 100+ TSV files. There is no join capability, no graph traversal, no query language. The "ontology graph" is ephemeral — rebuilt from scratch each hour.

A World Store solves this by:
- **Unified schema** — One store for experiments, contexts, tasks, memories, backends, strategies
- **Datalog queries** — `(find ?e :where (?e :backend "MiniMax") (?e :decision :failed))`
- **Persistent graph** — Relationships between experiment → strategy → backend → target
- **Branchable** — Isolated experiment branches, merge/promote workflow
- **Time-travel** — Datahike's temporal index enables historical analysis

## Requirements

### Functional

- [ ] Datahike installed and accessible from brepl
- [ ] Schema defined for: experiment, task, context, memory, backend, strategy, target
- [ ] All existing TSV experiment results migrated to World Store
- [ ] Context sidecars (.sexp) linked to experiment entities
- [ ] Datalog query helpers exposed via Emacs functions
- [ ] `parse-all-results` replaced with indexed queries
- [ ] Branch create/switch/merge/promote workflow
- [ ] Emacs integration: transact, query, entity lookup from Elisp

### Non-Functional

- [ ] Query latency < 100ms for common routing queries
- [ ] Store startup < 5s (cold) / < 1s (warm)
- [ ] Backward compatibility: TSV files remain as audit trail
- [ ] Graceful degradation: if Datahike unavailable, fall back to TSV parsing
- [ ] Schema migrations handled transparently
- [ ] Branching does not copy full database (Datahike filst-level branching)

## Scope

### In Scope

- Datahike installation and configuration
- Schema design and migration
- TSV → Datahike migration (all 5 schema versions)
- Context sidecar unification
- Query layer (Datalog + helper functions)
- Emacs/Elisp integration module
- Branching workflow (create, switch, merge, promote)
- Tests for all layers

### Out of Scope

- Real-time streaming ingestion (batch migration only)
- Distributed/multi-node Datahike
- Full-text search (Datahike's built-in indexing is sufficient)
- Web UI for browsing store
- Migration of mementum markdown files (schema index is in scope, content is not)

## Definition of Done

- [ ] All 2945 existing tests still pass
- [ ] New tests: Datahike CRUD (10), migration (5), query (10), branching (5), integration (5)
- [ ] `parse-all-results` usage eliminated from routing hot path
- [ ] Self-audit reports 0 data-integrity issues
- [ ] Documentation: schema reference, query cookbook, branching workflow
- [ ] Pi5 auto-evolution can read/write via the new store

## Testing Strategy

- **Unit tests**: Datahike schema validation, transaction helpers, query builders
- **Integration tests**: TSV migration round-trip, brepl connectivity, Emacs bridge
- **Property tests**: Random experiment data → transact → query → verify
- **Performance tests**: 10k experiments → query latency benchmark
- **Branching tests**: Create branch → write → merge → verify isolation

## Phases

| Phase | Title | Scope | Status |
|-------|-------|-------|--------|
| 1 | Bootstrap | Install Datahike, define schema, basic CRUD via brepl | pending |
| 2 | TSV Migration | Migrate all existing experiment TSVs to World Store | pending |
| 3 | Context Unification | Merge .sexp sidecars, approval history, risk patterns into unified entities | pending |
| 4 | Query Layer | Replace parse-all-results with Datalog queries; add query helpers | pending |
| 5 | Branching | Branchable stores for isolated experiments; merge/promote workflow | pending |

## Risks & Open Questions

| Risk/Question | Impact | Mitigation/Answer |
|---------------|--------|-------------------|
| Datahike may not work with babashka (pod required?) | High — blocks entire plan | Research Datahike babashka pod; fallback to deps.edn + clj CLI |
| Schema design errors are expensive to fix post-migration | Medium | Design schema carefully; use Datahike's flexible schema; test migrations |
| TSV has 5 schema versions with incompatible columns | Medium | Write per-version parsers; map all to unified schema; log unmappable fields |
| Performance: 10k+ experiments may slow queries | Medium | Add indices; benchmark early in Phase 2; consider compaction |
| Emacs→Clojure bridge adds latency | Low | Use brepl's nREPL; cache frequent queries; async where possible |
| Pi5 auto-evolution writes TSV directly | Medium | Add TSV→Store sync hook; or redirect Pi5 writes to store API |

## Changelog

### 2026-06-11

- Plan created
