---
type: planning
entity: plan
plan: "optimize-model-routing"
status: done
created: "2026-06-06"
updated: "2026-06-06"
---

# Plan: Optimize Model Routing Based on Task Type

## Objective

Implement automatic task type detection from prompt keywords to dynamically route to the optimal model, replacing the static routing table with a heuristic-based system.

## Motivation

Current model routing is static (defined in mementum/state.md). Users must manually select the right agent for each task. An automatic system would:
- Reduce cognitive load
- Improve response quality by matching model strengths to task requirements
- Reduce costs by using cheaper models for simple tasks

## Requirements

### Functional

- [ ] Define task type taxonomy (e.g., code, review, research, creative, debugging)
- [ ] Create keyword-to-task-type mapping
- [ ] Implement prompt analysis function that extracts task type
- [ ] Create dynamic routing function that selects model based on task type
- [ ] Add fallback mechanism when task type is ambiguous
- [ ] Allow manual override (user can still specify agent explicitly)

### Non-Functional

- [ ] Routing decision should take <10ms
- [ ] Should not add latency to API calls
- [ ] Backward compatible with existing agent definitions
- [ ] Configurable via mementum/knowledge/

## Scope

### In Scope

- Keyword extraction from prompts
- Task type classification
- Dynamic model selection
- Configuration storage in mementum

### Out of Scope

- Changing agent definitions (they stay the same)
- New model providers
- Prompt rewriting/optimization

## Definition of Done

- [x] Routing function implemented (gptel-backend-registry-select-for-task in gptel-ext-backend-registry.el)
- [x] Task-type taxonomy defined (gptel-task-type-model-defaults + gptel-fallback-chains)
- [x] Manual override works (gptel-benchmark-llm-model still overrides auto-select)
- [x] Tests pass (99/99)

## Testing Strategy

- Unit tests for routing function (test-gptel-ext-backend-registry.el)
- Unit tests for auto-select with registry (test-gptel-benchmark-llm.el)
- Integration tests for full pipeline (test-auto-workflow.el)

## Phases

| Phase | Title | Scope | Status |
|-------|-------|-------|--------|
| 1 | Task Type Taxonomy | Define keywords and task types | done — gptel-task-type-model-defaults |
| 2 | Routing Function | Implement dynamic routing | done — gptel-backend-registry-select-for-task |
| 3 | Integration | Wire into agent dispatch | done — all 7 OV5 files updated |

## Risks & Open Questions

| Risk | Impact | Mitigation |
|------|--------|------------|
| Keyword-based routing may misclassify | Medium | Add confidence score, fallback to default |
| Adding latency to every request | Low | Cache classifications |
| Users may prefer manual control | Low | Always allow manual override |

## Changelog

### 2026-06-10

- Plan completed. Implemented as registry-based smart routing (gptel-backend-registry-select-for-task) rather than keyword-based classification. Replaced 17 hardcoded backend references across 7 files. Commit 37dcacde4.

### 2026-06-06

- Plan created
