# Monitoring Agent Module

## Purpose

Phase 2 of YC vision: monitoring agent that analyzes failures and rewrites the pipeline itself. The "holy shit moment" — a system that improves its own improvement mechanisms.

## Tasks

### Task 2.1: Failure Pattern Analysis

Detects 4 systemic failure types:
1. **Grader systematic failures** — 3+ failures on similar code
2. **Backend-category failures** — <5% keep-rate with 20+ experiments
3. **Effort waste** — high effort without improvement
4. **Target failure loops** — 5+ failures on same target

### Task 2.2: Self-Improvement Proposals

| Pattern | Proposal |
|---|---|
| Grader systematic | Grader rewrite with test plan |
| Backend failing | Backend swap proposal |
| Effort waste | Effort level downgrade |
| Target loop | Target skip with investigation |

### Task 2.3: Automated Testing & Deployment

- Baseline keep-rate calculation
- Improvement delta measurement
- Deploy/reject decisions based on measured improvement
- Deployment logging for audit trail

## Key Functions

| Function | Purpose |
|---|---|
| `gptel-monitoring-agent--parse-results` | Parse TSV experiment results |
| `gptel-monitoring-agent--filter-by-decision` | Filter by decision type |
| `gptel-monitoring-agent--group-by-backend-category` | Group by backend + category |
