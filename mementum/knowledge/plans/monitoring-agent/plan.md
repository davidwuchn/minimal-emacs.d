---
type: planning
entity: plan
plan: "monitoring-agent"
status: draft
created: "2026-06-06"
updated: "2026-06-06"
---

# Plan: Monitoring Agent (YC Phase 2 — "Holy Shit Moment")

## Objective

Implement a meta-improvement layer that watches the OV5 pipeline, detects systemic failures, proposes fixes for the pipeline components themselves, and auto-deploys improvements. This is YC's "holy shit moment" — a system that improves its own improvement mechanisms.

## Motivation

OV5 currently has:
- ✅ Self-healing (fixes symptoms: RSS watchdog, TSV integrity, silent failure logging)
- ✅ Self-evolution (synthesizes patterns from successful experiments)
- ❌ **Meta-improvement** (rewriting the grader itself when it fails repeatedly)

Without the monitoring agent, OV5 optimizes experiments but never questions whether the experiment pipeline itself is optimal. The monitoring agent closes this loop by asking:

> "The grader failed 3 times on similar code. Should we rewrite the grader?"

## Requirements

### Functional

- [ ] Parse TSV experiment logs to detect systemic failure patterns
- [ ] Identify recurring failures (same failure mode, same component, same target)
- [ ] Generate improvement proposals for pipeline components
- [ ] Test proposals against historical failures
- [ ] Auto-deploy if improvement > threshold (60% success rate)
- [ ] Track grader accuracy, keep rate, and quality score trends
- [ ] Surface monitoring agent decisions in mementum

### Non-Functional

- [ ] Run asynchronously (non-blocking to experiment pipeline)
- [ ] Throttle analysis (max 1 cycle per 15 minutes)
- [ ] Persist failure patterns and proposals to mementum
- [ ] Safe rollback if proposal makes things worse
- [ ] Human-in-the-loop for high-risk proposals

## Scope

### In Scope

- New module: `lisp/modules/gptel-auto-workflow-monitoring-agent.el`
- Failure pattern analysis across TSV logs
- Proposal generation for: grader, prompt builder, strategy harness
- Historical validation of proposals
- Auto-deployment with rollback
- Integration with mementum for persistence

### Out of Scope

- Rewriting external dependencies (gptel, nucleus)
- Production monitoring (Phase 1 — already implemented)
- Context database (Phase 3 — already implemented)
- Human interface layer (Phase 4 — already implemented)

## Definition of Done

- [ ] Monitoring agent module created and loaded
- [ ] Detects recurring failures with >80% accuracy
- [ ] Generates 1+ proposal per week for systemic failures
- [ ] Tests proposals against historical data
- [ ] Auto-deploys if success rate > 60%
- [ ] All changes committed and pushed
- [ ] TDD tests pass

## Testing Strategy

- Unit tests: failure pattern detection, proposal generation
- Integration tests: full cycle (detect → propose → test → deploy)
- Historical validation: run against past TSV data
- Rollback tests: verify safe rollback works

## Phases

| Phase | Title | Scope | Status |
|-------|-------|-------|--------|
| 1 | Failure Pattern Analysis | [Detail](phases/phase-1.md) | pending |
| 2 | Proposal Generation | [Detail](phases/phase-2.md) | pending |
| 3 | Auto-Test & Deploy | [Detail](phases/phase-3.md) | pending |

## Risks & Open Questions

| Risk/Question | Impact | Mitigation/Answer |
|---------------|--------|-------------------|
| Proposal generation may hallucinate fixes | HIGH | Validate against historical data before deployment |
| Infinite loop: agent rewrites itself poorly | HIGH | Throttle + human approval for meta-changes |
| TSV format changes break analysis | MEDIUM | Version TSV schema, handle gracefully |
| False positive patterns | MEDIUM | Require 3+ occurrences before triggering |
| Rollback complexity | MEDIUM | Git worktree isolation, keep previous version |

## Changelog

### 2026-06-06

- Plan created
