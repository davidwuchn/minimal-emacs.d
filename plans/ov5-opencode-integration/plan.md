---
title: OV5 OpenCode Integration Plan
status: active
category: integration
---

# OV5 OpenCode Integration Plan

## Objective

Make OV5 work seamlessly with OpenCode Processing Skills (OPS), using **mementum as the source of truth**.

## Principle

> `mementum/` is the single source of truth. `docs/` is a navigation layer that references it.

## Current State

- **mementum/** — Git-based memory (working memory, insights, knowledge)
- **plans/** — OPS plan directory (new)
- **docs/** — OPS navigation layer (references mementum)
- **scripts/** — Pipeline scripts + OPS install script

## Goals

1. **Mementum-first documentation** — docs/ references mementum/
2. **OPS plan integration** — use create-plan for features
3. **Session handover** — generate-handover writes to mementum/state.md
4. **Pipeline + OPS** — pipeline execution triggers OPS plan updates

## Phases

### Phase 1: Mementum as Docs (Done)
- docs/overview.md → references mementum/knowledge/
- docs/modules/ → references mementum/knowledge/project-facts.md

### Phase 2: Plan Integration (In Progress)
- plans/ uses OPS create-plan skill
- plan.md references mementum for context
- todo.md syncs with mementum/state.md

### Phase 3: Session Handover (Next)
- generate-handover writes to mementum/state.md
- resume-plan reads from mementum/

### Phase 4: Pipeline + OPS (Future)
- Pipeline execution triggers plan updates
- Experiment results stored in mementum/memories/
- OPS agents execute plan phases

## Acceptance Criteria

- [x] docs/overview.md references mementum/
- [ ] plans/ uses OPS format with mementum context
- [ ] generate-handover updates mementum/state.md
- [ ] resume-plan reads mementum/
- [ ] Pipeline results stored in mementum/memories/

## Next Steps

1. Create first OPS plan using create-plan skill
2. Generate handover for this session
3. Test resume-plan from mementum/
