---
type: planning
entity: plan
plan: document-ov5-modules
session_date: 2026-06-06
---

# Document All 39 OV5 Modules

## Objective

Create OPS-style documentation for all 39 Emacs Lisp modules in `lisp/modules/`, starting with the core subsystems. Enable `@maintainer` and `doc-explorer` agents to navigate and understand the codebase without rediscovery.

## Motivation

OV5 has 39 modules but no comprehensive documentation. Every session rediscovers module purposes, dependencies, and entry points. This wastes context window and limits the effectiveness of AI-assisted development.

## Requirements

### Functional

- Each module gets a `docs/modules/<module-name>.md` file
- Module docs include: purpose, key functions, dependencies, integration points
- Cross-references between modules
- Module docs reference mementum knowledge where applicable

### Non-Functional

- Docs must be accurate (verified against code)
- Docs must stay in sync (update-docs skill)
- Prefer auto-generation from code where possible

## Scope

**In scope:**
- Document all 39 `lisp/modules/` files
- Create module index in `docs/modules/README.md`
- Cross-reference mementum knowledge

**Out of scope:**
- Refactoring modules (docs only)
- Tests for documentation
- External dependencies (packages/, etc.)

## Definition of Done

- [ ] All 39 modules have docs/modules/*.md
- [ ] docs/modules/README.md exists with index
- [ ] Module docs verified against current code
- [ ] update-docs skill can refresh docs

## Testing Strategy

- Manual review: spot-check 5 random modules for accuracy
- update-docs: verify it detects changes and updates correctly

## Phases

| Phase | Title | Description |
|---|---|---|
| 1 | Core Subsystems | Document mementum, pipeline, evolution, self-heal modules |
| 2 | Agent Modules | Document gptel-tools-agent-* modules |
| 3 | Workflow Modules | Document gptel-auto-workflow-* modules |
| 4 | Extension Modules | Document gptel-ext-* and other modules |
| 5 | Index & Verification | Create README, cross-references, verify |

## Risks

- **Module churn**: Pi5 may modify modules while documenting. Mitigation: frequent commits, update-docs skill.
- **Doc drift**: Docs get stale. Mitigation: update-docs skill integration.
- **Scope creep**: Wanting to refactor while documenting. Mitigation: docs-only, no code changes.

## Open Questions

- Should we use doc-explorer to auto-generate first drafts?
- How do we handle protected modules (e.g., strategic, production)?

## Changelog

- **2026-06-06**: Plan created
