---
title: Skill Architecture - Protocol vs Tool Skills
status: active
category: knowledge
tags: [skills, protocols, mementum, architecture, tooling]
---

# Skill Architecture: Protocol vs Tool Skills

## Overview

This document defines the foundational architecture for organizing skills in the system. Understanding the distinction between **Protocol Skills** and **Tool Skills** is essential for effective knowledge consolidation and skill management.

The core principle: **Store pure procedures in Mementum; wrap external dependencies in Skills.**

## The Two-Skill Taxonomy

Skills in the system fall into two categories based on their dependencies:

### Protocol Skills

Protocol skills contain pure procedures, decision matrices, and behavioral patterns that require no external systems. They are the "know-how" that drives execution.

| Characteristic | Description |
|----------------|-------------|
| Dependencies | None (self-contained) |
| Content | Procedures, decision matrices, patterns |
| Storage | `mementum/knowledge/{name}-protocol.md` |
| Examples | learning, planning, sarcasmotron, tutor |

### Tool Skills

Tool skills require external systems to function—REPLs, APIs, CLIs, or other runtime environments. They provide the interface between pure logic and concrete execution.

| Characteristic | Description |
|----------------|-------------|
| Dependencies | REPL, API, CLI, external scripts |
| Content | Tool wrappers, integration code, protocol reference |
| Storage | `skills/{name}/` directory |
| Examples | clojure-expert, reddit, requesthunt, seo-geo |

## How They Work Together

The architecture creates a clean separation between **what to do** (protocol) and **how to interact with systems** (tool):

```
┌─────────────────────────────────────────────────────────────┐
│                        AGENTS.md                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Tool Skill (skill/)                       │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ depends: mementum/knowledge/{domain}-protocol.md    │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│         ┌─────────────────┼─────────────────┐              │
│         ▼                 ▼                 ▼              │
│  ┌────────────┐   ┌────────────┐   ┌────────────┐          │
│  │ REPL Tool  │   │  API Tool  │   │ CLI Tool   │          │
│  └────────────┘   └────────────┘   └────────────┘          │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────────┐   ┌─────────────────────────────┐
│  Protocol Skill (mementum)  │   │   Tool Executes → Result    │
│                             │   └─────────────────────────────┘
│  # {domain}-protocol.md     │
│                             │
│  ## Procedures             │
│  ## Decision Matrices       │
│  ## Behavioral Patterns     │
└─────────────────────────────┘
```

### Execution Flow

```
AI reads protocol (mementum/knowledge/learning-protocol.md)
    │
    ▼
Understands procedures and decision matrices
    │
    ▼
Determines need for external system
    │
    ▼
Calls tool skill (e.g., clojure-expert) for REPL access
    │
    ▼
Gets result → applies protocol logic → produces output
```

## Skill Component Mapping to Mementum

When consolidating skills, map components to their Mementum equivalents:

| Skill Component | Mementum Equivalent | Storage Location |
|-----------------|---------------------|------------------|
| `λ(observe)` | `store` | `mementum/state.md` |
| `λ(learn)` | `recall` | `mementum/knowledge/` |
| `λ(evolve)` | `metabolize` | `mementum/memories/` |
| `instincts/personal/` | `mementum/memories/` | `mementum/memories/` |
| `instincts/library/` | `mementum/knowledge/` | `mementum/knowledge/` |
| Session state | State tracking | `mementum/state.md` |
| Project facts | Knowledge base | `mementum/knowledge/project-facts.md` |
| Procedural content | Protocol | `mementum/knowledge/{domain}-protocol.md` |

## Protocol Skill Pattern

Protocol skills live in `mementum/knowledge/` and contain pure procedural content.

### Frontmatter Structure

```yaml
---
title: Learning Protocol
status: active
category: protocol
tags: [learning, protocol, procedures]
depends: []
---

# Learning Protocol
```

### Content Structure

```markdown
## Procedures

### Observation Phase
1. Identify information gap
2. Query existing knowledge
3. Determine learning strategy

### Integration Phase
1. Acquire new information
2. Validate against existing model
3. Update knowledge structure

### Application Phase
1. Test understanding in context
2. Refine based on feedback
3. Consolidate into memory

## Decision Matrix

| Situation | Action |
|-----------|--------|
| Unknown topic | Query → Acquire → Validate |
| Partial knowledge | Identify gaps → Targeted learning |
| Known topic | Skip acquisition → Apply directly |
```

## Tool Skill Pattern

Tool skills live in `skills/{name}/` and wrap external dependencies.

### Frontmatter Structure

```yaml
---
title: Clojure Expert
status: active
category: tool
tags: [clojure, repl, expert]
depends:
  - mementum/knowledge/programming-protocol.md
---

# Clojure Expert
```

### Content Structure

```markdown
## Protocol Reference

See [mementum/knowledge/programming-protocol.md](mementum/knowledge/programming-protocol.md) for idiomatic patterns, code review criteria, and design principles.

## Tool Integration

This skill provides REPL access for Clojure development.

### Available Tools

- `clojure-eval`: Execute Clojure code in REPL
- `clojure-load-file`: Load namespace and dependencies
- `clojure-test`: Run test suite

### Usage Example

```
User: "Write a function that computes Fibonacci"

AI reads programming-protocol.md for approach
    │
    ▼
Calls clojure-eval with generated code
    │
    ▼
Gets result → validates against protocol → returns
```

## Architecture Before and After

### Before (Indirect)

```
AGENTS.md → skills/ → SKILL.md → procedures → memories
                └─ thin wrapper adds indirection
```

### After (Direct)

```
AGENTS.md → mementum/ → knowledge/protocol.md → direct execution
                 │
                 └─ pure procedure, no wrapper needed
```

## When to Apply Each Pattern

| Condition | Action |
|-----------|--------|
| Skill contains only procedures/matrices | Migrate to `mementum/knowledge/{name}-protocol.md` |
| Skill requires REPL/API/scripts | Keep skill, extract protocol, add `depends:` |
| Protocol shared across multiple skills | Single source in `mementum/knowledge/` |
| Skill has persistent state | Use `mementum/state.md` |
| Skill contains instincts/patterns | Use `mementum/memories/` |

## Migration Checklist

When migrating a skill to this architecture:

1. [ ] Identify pure procedural content
2. [ ] Extract protocol to `mementum/knowledge/{domain}-protocol.md`
3. [ ] Identify external dependencies
4. [ ] Keep tool wrapper in `skills/{name}/`
5. [ ] Add `depends:` frontmatter to tool skill
6. [ ] Add Protocol Reference section to tool skill
7. [ ] Remove duplicate content from original skill
8. [ ] Update AGENTS.md if referenced

## Common Patterns

### Decision Matrix Pattern

```markdown
## Decision Matrix: Approach Selection

| Context | Complexity | Available Time | Approach |
|---------|------------|----------------|----------|
| Unknown domain | Any | Limited | Research-first |
| Known domain | High | Ample | Deep implementation |
| Known domain | Low | Any | Direct implementation |
| Time pressure | Any | Limited | Prototype-first |
```

### Tool Invocation Pattern

```markdown
## Tool Invocation

When the protocol requires execution:

1. Parse protocol requirements
2. Select appropriate tool from available tools
3. Construct tool input from protocol specifications
4. Execute tool call
5. Validate output against protocol expectations
6. Return result or iterate
```

### Protocol Composition Pattern

```markdown
## Composing Protocols

Multiple protocols can compose:

- learning-protocol.md: How to learn new concepts
- programming-protocol.md: How to implement correctly  
- review-protocol.md: How to validate quality

The AI chains these based on task requirements.
```

## Summary

The skill architecture reduces indirection by separating concerns:

- **Protocols** are pure knowledge—procedures, decisions, patterns—stored directly in Mementum
- **Tools** are thin wrappers around external systems that reference protocols
- **Skills** are either protocols (self-contained) or tools (dependent on external systems)

This architecture simplifies maintenance, reduces duplication, and enables protocol sharing across multiple tool skills.

---

## Related

- [Mementum Knowledge Structure](mementum/knowledge/)
- [Tool Integration Patterns](skills/)
- [State Management](mementum/state.md)
- [Memory Organization](mementum/memories/)
- [Project Knowledge](mementum/knowledge/project-facts.md)