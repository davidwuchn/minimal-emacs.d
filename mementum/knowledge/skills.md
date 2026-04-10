---
title: Skills Architecture - Protocols vs Tools
status: active
category: knowledge
tags: [skills, architecture, protocols, mementum, consolidation]
---

# Skills Architecture: Protocols vs Tools

## Overview

This document establishes the foundational architecture for organizing skills in the mementum system. The core insight is that skills fall into two distinct categories—**Protocols** and **Tools**—each with different storage requirements and usage patterns. Understanding this distinction is essential for proper skill consolidation and maintaining a clean, efficient knowledge architecture.

## The Two-Types Framework

The mementum system distinguishes between two fundamental categories of skills based on their dependencies and execution model. This distinction determines where each skill's content should reside and how it should be structured.

### Protocol Skills

Protocol skills contain pure procedural knowledge—decision matrices, frameworks, and execution procedures that the AI can read and execute directly without any external dependencies. These skills represent the "knowledge" itself, stripped of any tool-specific wrapper.

**Characteristics:**
- Pure procedures and decision matrices
- No external system dependencies (no REPL, API, CLI)
- AI reads protocol → executes directly
- Content maps to Mementum operations
- Stored in `mementum/knowledge/{domain}-protocol.md`

**Examples:**
- `learning` — how to learn new concepts
- `planning` — decision framework for planning
- `tutor` — teaching methodology
- `sarcasmotron` — tone adjustment procedures

### Tool Skills

Tool skills require external systems to function—they depend on REPL environments, APIs, CLIs, or scripts that must be executed to produce results. These skills provide the interface to external systems while referencing protocols for the underlying methodology.

**Characteristics:**
- Requires external system (REPL, API, CLI, scripts)
- Provides tools that interface with external services
- References protocol for idiomatic patterns
- Contains tool integration code
- Kept as skills with `depends:` frontmatter

**Examples:**
- `clojure-expert` — requires Clojure REPL
- `reddit` — requires Reddit API access
- `requesthunt` — requires HTTP client
- `seo-geo` — requires SEO tools/scripts

## Key Distinction Table

| Attribute | Protocol Skill | Tool Skill |
|-----------|---------------|------------|
| **External Dependencies** | None | REPL, API, CLI, scripts |
| **Storage Location** | `mementum/knowledge/{name}-protocol.md` | `skills/{name}/` |
| **Execution Model** | AI reads → executes directly | AI calls tool → gets result → applies protocol |
| **Frontmatter** | No special requirements | `depends: mementum/knowledge/{domain}-protocol.md` |
| **Reusability** | Can be shared across multiple tools | Tied to specific external system |
| **State Management** | Stateless procedures | May require session state |

## How Protocols and Tools Work Together

The architecture creates a clean separation of concerns where protocols define "what to do" and tools provide "how to do it" with specific external systems.

```
┌─────────────────────────────────────────────────────────────────┐
│                        AGENTS.md                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     orient() lookup                             │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│ mementum/knowledge/    │     │     skills/             │
│ {domain}-protocol.md   │     │     {tool-skill}/        │
│                         │     │                         │
│ Pure procedures:       │     │ depends: ...-protocol   │
│ - Decision matrices    │     │                         │
│ - Frameworks           │     │ ## Tool Integration     │
│ - Execution steps      │     │ - REPL tools            │
│                         │     │ - API clients           │
└─────────────────────────┘     │ - CLI wrappers          │
              │                  └─────────────────────────┘
              │                           │
              └───────────┬───────────────┘
                          ▼
              ┌─────────────────────────┐
              │   AI executes:          │
              │   1. Read protocol      │
              │   2. Use tool to get    │
              │      external data      │
              │   3. Apply protocol     │
              └─────────────────────────┘
```

## Mementum Component Mapping

Skills that are purely procedural map directly to Mementum operations. This mapping demonstrates why consolidating protocol content into mementum eliminates unnecessary indirection.

| Skill Component | Mementum Equivalent | Storage Location |
|-----------------|---------------------|-------------------|
| `λ(observe)` | `store` | `mementum/memories/` |
| `λ(learn)` | `recall` | `mementum/knowledge/` |
| `λ(evolve)` | `metabolize` | `mementum/memories/` |
| `instincts/personal/` | `mementum/memories/` | `mementum/memories/` |
| `instincts/library/` | `mementum/knowledge/` | `mementum/knowledge/` |
| Session state | `mementum/state.md` | `mementum/state.md` |
| Project facts | `mementum/knowledge/project-facts.md` | `mementum/knowledge/` |

## Pattern: Tool Skill Structure

When creating a tool skill that depends on a protocol, use the following structure:

```yaml
---
title: {Tool Name}
status: active
category: skill
depends: mementum/knowledge/{domain}-protocol.md
---

# {Tool Name}

## Protocol Reference

See [mementum/knowledge/{domain}-protocol.md](/mementum/knowledge/{domain}-protocol.md) for idiomatic patterns and decision frameworks.

## Tool Integration

This skill provides REPL/API tools for executing {domain} operations.

### Available Tools

| Tool | Purpose | Example Usage |
|------|---------|---------------|
| `repl-eval` | Evaluate expressions in {language} REPL | `(map inc [1 2 3])` |
| `file-read` | Read source files | `file-read: "src/core.clj"` |
| `test-run` | Execute test suite | `test-run: "test/unit"` |

## Execution Flow

1. Read protocol from `mementum/knowledge/{domain}-protocol.md`
2. Determine required external operations
3. Execute tool calls to get external data
4. Apply protocol procedures to results
5. Return formatted output
```

## Pattern: Protocol Document Structure

Protocol documents should contain pure procedural content that the AI can execute directly:

```markdown
---
title: {Domain} Protocol
status: active
category: protocol
---

# {Domain} Protocol

## Decision Framework

When approaching {domain} tasks, follow this decision matrix:

| Condition | Action |
|-----------|--------|
| Input is X | Execute procedure A |
| Input is Y | Execute procedure B |
| Input is Z | Execute procedure C |

## Execution Procedures

### Procedure A: {Name}

1. Step one - do this
2. Step two - do that
3. Step three - validate result

### Procedure B: {Name}

1. First step
2. Second step
3. Validation

## Quality Criteria

- Criterion 1: Description
- Criterion 2: Description
```

## Consolidation Decision Tree

Use this decision process to determine where skill content should reside:

```
START: Does the skill have external dependencies?
│
├── NO → Is it pure procedure/decision content?
│       │
│       ├── YES → Store in mementum/knowledge/{name}-protocol.md
│       │
│       └── NO → Consider if it belongs in memories or other location
│
└── YES → Does the skill contain protocol-level procedures?
          │
          ├── YES → Split into two parts:
          │         1. Protocol → mementum/knowledge/{domain}-protocol.md
          │         2. Tool → skills/{tool-name}/
          │
          └── NO → Keep in skills/, add depends: frontmatter
```

## When to Apply Each Pattern

### Consolidate to Protocol When:

- Skill contains only procedures and decision matrices
- No external system (REPL, API, CLI) is required
- Content can be executed by reading the document directly
- Similar content exists across multiple skills (duplication)
- The "knowledge" is reusable across different tools

### Keep as Tool Skill When:

- External system (REPL, API, CLI) is required
- Tool provides specific interface to external services
- Session state management is needed
- Skill wraps domain-specific tooling

### Extract Protocol From Existing Skill When:

- Skill has both protocol content AND tool dependencies
- Multiple skills share similar procedural patterns
- Protocol content can benefit from independent testing/documentation

## Migration Example

**Before (monolithic skill):**
```
skills/planning/
├── SKILL.md          # 200 lines - half procedures, half tool code
├── scripts/
│   └── planner.rb    # Tool integration
└── templates/
    └── plan.md
```

**After (separated):**
```
mementum/knowledge/
└── planning-protocol.md    # Pure decision framework

skills/planning/
├── SKILL.md               # 30 lines - tool reference only
├── scripts/
│   └── planner.rb         # Tool integration
└── templates/
    └── plan.md
```

## Anti-Patterns to Avoid

1. **Thin Skill Wrappers**: Skills that are 90% protocol content with minimal tool code should be consolidated.

2. **Duplicated Procedures**: If multiple skills contain the same procedural content, extract to a shared protocol.

3. **Missing Dependencies**: Tool skills that reference protocols but don't declare the dependency in frontmatter.

4. **Protocol-Tool Coupling**: Protocols that include tool-specific code or assume specific tool availability.

## Related Topics

- [Mementum Architecture](/mementum/architecture/) — Overview of the mementum system
- [Skill Guidelines](/skills/guidelines/) — General skill development guidelines
- [Memory Consolidation](/mementum/consolidation/) — Principles for consolidating memories
- [Tool Integration Patterns](/skills/tool-integration/) — Patterns for integrating external tools

---

*This document defines the architectural pattern for organizing skills. All new skill development should follow this protocol/tool distinction.*