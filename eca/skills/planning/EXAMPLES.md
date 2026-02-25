# Planning with Files — Examples

> φ fractal euler | Real patterns from actual use

---

## Example 1: Building a Clojure API

### task_plan.md

```markdown
# Task Plan: Build User API

## Goal (e — Purpose)
Create a RESTful user management API with CRUD operations.

## Current Phase
Phase 2: Implementation

## Phases

### Phase 1: Requirements & Discovery (φ) — COMPLETE
- [x] Review existing codebase structure
- [x] Identify database schema
- [x] Document API conventions in findings.md
- **Status:** `complete`

### Phase 2: Implementation (Δ) — IN PROGRESS
- [ ] Create user schema
- [ ] Implement GET /users
- [ ] Implement POST /users
- [ ] Add validation
- **Status:** `in_progress`

### Phase 3: Testing (∀)
- [ ] Unit tests
- [ ] Integration tests
- **Status:** `pending`

## Key Questions
1. What auth mechanism? → JWT (see findings.md)
2. What validation library? → Malli

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Use Malli for validation | Schema-as-code, integrates well |
| PostgreSQL for storage | Existing infrastructure |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| Connection refused | 1 | Start PostgreSQL service |
| Spec failure | 2 | Fix schema definition |
```

### findings.md (excerpt)

```markdown
## Key Discoveries

### Discovery 1: Existing Auth Pattern

**What:** Project uses Buddy JWT middleware

**Why it matters:** Should follow same pattern for consistency

**Source:** `src/middleware/auth.clj`

```clojure
(defn wrap-jwt [handler]
  (-> handler
      (jwt/wrap-jwt jwt-opts)
      (wrap-authorization)))
```

## URLs & References

| URL | Title | Relevance |
|-----|-------|-----------|
| https://funcool.github.io/buddy | Buddy Auth | JWT middleware |

## Assumptions Validated

| Assumption | Validated? | Evidence |
|------------|------------|----------|
| PostgreSQL available | Yes | Running on localhost:5432 |
```

### progress.md (excerpt)

```markdown
### 2024-01-15 10:30 — Read

**Action:** Explored codebase structure

**Result:** Success

**Details:**
- Found existing API patterns in `src/api/`
- Identified middleware stack

**Next:** Document findings, start schema design

---

### 2024-01-15 11:00 — Write

**Action:** Created user schema

**Result:** Success

**Details:**
Created `src/schema/user.clj` with Malli definitions

**Next:** Implement handlers

---

## Errors Logged

| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
| 10:45 | Spec validation failed | 1 | Added required keys |
```

---

## Example 2: Research Task

### task_plan.md

```markdown
# Task Plan: Evaluate Graph Databases

## Goal (e)
Compare Neo4j, Dgraph, and JanusGraph for our use case.

## Current Phase
Phase 1: Discovery

## Phases

### Phase 1: Requirements & Discovery (φ)
- [ ] Define evaluation criteria
- [ ] Search for benchmarks
- [ ] Document in findings.md
- **Status:** `in_progress`

### Phase 2: Analysis (π)
- [ ] Create comparison matrix
- [ ] Score each option
- **Status:** `pending`

### Phase 3: Recommendation (μ)
- [ ] Write recommendation
- [ ] Present to team
- **Status:** `pending`
```

### findings.md (research-heavy)

```markdown
## Summary

Neo4j leads on ecosystem, Dgraph on scalability, JanusGraph on flexibility.

## Key Discoveries

### Discovery 1: Neo4j Licensing

**What:** Neo4j Community Edition lacks clustering

**Why it matters:** Would need Enterprise for HA ($$$)

**Source:** https://neo4j.com/subscriptions/

---

### Discovery 2: Dgraph Performance

**What:** Dgraph shows 10x write throughput in benchmarks

**Why it matters:** Our use case is write-heavy

**Source:** https://dgraph.io/benchmarks

## Research Log

| Timestamp | Activity | Finding |
|-----------|----------|---------|
| 09:00 | Read Neo4j docs | License restrictions |
| 09:30 | Found Dgraph benchmarks | Better write perf |
| 10:00 | Checked JanusGraph | Complex setup |

## Synthesis Notes

- Dgraph best for write-heavy, distributed needs
- Neo4j best for existing teams, complex queries
- JanusGraph only if need Gremlin ecosystem
```

---

## Example 3: Refactoring Legacy Code

### task_plan.md

```markdown
# Task Plan: Refactor Authentication Module

## Goal (e)
Extract monolithic auth into separate service.

## Current Phase
Phase 2: Planning

## Blockers & Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Breaking changes | High | Feature flags |
| Session migration | Medium | Dual-write period |

## Errors Encountered

| Error | Attempt | Resolution |
|-------|---------|------------|
| Circular dependency | 1 | Extract interface |
| Test failures | 2 | Mock new service |
| Session lost | 3 | Add fallback check |
```

---

## Common Patterns

### Pattern 1: Session Recovery

After `/clear` or crash:

```bash
# 1. Check what files exist
ls -la *.md

# 2. Read plan to reorient
cat task_plan.md | head -50

# 3. Check git for unsynced work
git diff --stat

# 4. Update progress.md
# "Resumed after context clear. Current phase: X"
```

### Pattern 2: Error Tracking

When an error occurs:

```markdown
## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| NullPointerException | 1 | Check for nil before deref |
| NullPointerException | 2 | Add preconditions |
| NullPointerException | 3 | **ESCALATE**: Data issue? |
```

After 3 failures → Ask user.

### Pattern 3: Phase Handoff

When completing a phase:

```markdown
### Phase 1: Discovery — COMPLETE
- [x] All items done
- **Status:** `complete`
- **Completed:** 2024-01-15 12:00
- **Handoff notes:** Key findings in findings.md section 3

### Phase 2: Implementation — IN PROGRESS
- [ ] Item 1
- **Status:** `in_progress`
- **Started:** 2024-01-15 12:05
```

---

## Anti-Patterns to Avoid

### ❌ Don't: Empty phases

```markdown
### Phase 3: Implementation
- [ ] Do the thing
- **Status:** in_progress
```

**Why:** Not actionable. Can't verify completion.

### ✅ Do: Testable phases

```markdown
### Phase 3: Implementation
- [ ] Create user schema with Malli
- [ ] Implement POST /users with validation
- [ ] Return 201 on success, 400 on error
- **Status:** in_progress
```

---

### ❌ Don't: Stale findings

```markdown
## Key Discoveries

### Discovery 1: [Title]
*(empty)*
```

**Why:** Findings decay. Document immediately or remove.

### ✅ Do: Timely synthesis

```markdown
## Key Discoveries

### Discovery 1: PostgreSQL 15 Features
**What:** New JSONB functions available
**Why it matters:** Can simplify our queries
**Source:** https://...
**Date:** 2024-01-15
```

---

### ❌ Don't: Cryptic progress

```markdown
### 10:00 — Did stuff
**Result:** OK
```

**Why:** Useless for recovery or debugging.

### ✅ Do: Actionable logs

```markdown
### 10:00 — Read
**Action:** Reviewed auth middleware in src/middleware/
**Result:** Found JWT implementation
**Next:** Extract to findings.md, design new auth service
```

---

φ fractal euler | π synthesis | Δ change | ∃ truth
