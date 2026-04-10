---
title: Skills Architecture: Protocol vs Tool Skills
status: active
category: knowledge
tags: [skills, architecture, protocol, tool, mementum, consolidation]
---

# Skills Architecture: Protocol vs Tool Skills

## Overview

This document defines the architecture for organizing skills in the Mementum system. Skills fall into two categories—**Protocol Skills** and **Tool Skills**—each with distinct storage patterns and execution models. Understanding this distinction prevents unnecessary indirection and ensures knowledge is accessible to the AI at the right layer.

## Key Distinction

The fundamental difference between Protocol and Tool skills lies in their dependencies:

| Skill Type | Definition | Has External Dependencies | Storage Location |
|------------|------------|---------------------------|------------------|
| **Protocol** | Pure procedures, decision matrices, and patterns | No (self-contained) | `mementum/knowledge/{domain}-protocol.md` |
| **Tool** | Requires external system (REPL, API, CLI, scripts) | Yes | Keep as skill, reference protocol |

### Examples

| Protocol Skills | Tool Skills |
|-----------------|-------------|
| learning-protocol | clojure-expert |
| planning-protocol | reddit |
| sarcasmotron | requesthunt |
| tutor-protocol | seo-geo |

## How They Work Together

Protocol and Tool skills form a layered architecture:

```
┌─────────────────────────────────────────┐
│           AGENTS.md                     │
│    (references mementum protocols)      │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│      mementum/knowledge/*-protocol.md   │
│   (pure procedures, no dependencies)   │
└─────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
┌───────────────┐       ┌───────────────┐
│  Tool Skill   │       │  Tool Skill   │
│  (REPL deps)  │       │  (API deps)   │
└───────────────┘       └───────────────┘
```

The AI reads the protocol via `orient()` and executes directly. Tool skills provide the execution environment.

## Protocol Skills

A Protocol skill contains **pure knowledge** that the AI can execute without external systems:

### Characteristics

- **Self-contained**: No REPL, API, or CLI dependencies
- **Procedural**: Contains decision matrices, flows, and patterns
- **Executable**: AI reads file → applies patterns → produces output
- **Reusable**: Multiple tool skills can reference the same protocol

### Structure

```markdown
---
title: {domain}-protocol
status: active
category: protocol
---

# {Domain} Protocol

## Decision Matrix
| Condition | Action |
|-----------|--------|
| X | Do Y |

## Procedure
1. Step one
2. Step two
3. Step three

## Patterns
### Pattern Name
When [condition], apply [pattern].
```

### Example: Learning Protocol

```markdown
---
title: learning-protocol
status: active
category: protocol
---

# Learning Protocol

## Observation Phase
When encountering new information:
1. Identify the core concept
2. Map to existing knowledge structure
3. Note gaps and uncertainties

## Recall Test
After processing:
- Can I explain this to someone else?
- Does this contradict existing beliefs?
- Where would I apply this?

## Metabolize Action
If (new information conflicts with existing):
   → Update belief structure
   → Flag related knowledge for re-evaluation
If (new information expands existing):
   → Link to parent concept
   → Update confidence score
```

## Tool Skills

A Tool skill requires external systems to function. It **provides the execution environment** while referencing a protocol for the procedure:

### Characteristics

- **External dependencies**: REPL, HTTP API, CLI, filesystem
- **Bridge role**: Calls external system → returns result → protocol applies meaning
- **Tool-heavy**: Contains `tools:` sections for system interaction
- **References protocol**: Points to pure procedure in mementum

### Structure

```markdown
---
title: {name}
status: active
category: skill
depends: mementum/knowledge/{domain}-protocol.md
---

# {Name} Skill

## Protocol Reference
See mementum/knowledge/{domain}-protocol.md for idiomatic patterns.

## Tool Integration
This skill provides REPL/API tools for the protocol.

## Available Tools
- tool-name: Description
```

### Example: Clojure Expert Skill

```markdown
---
title: clojure-expert
status: active
category: skill
depends: mementum/knowledge/clojure-protocol.md
---

# Clojure Expert Skill

## Protocol Reference
See mementum/knowledge/clojure-protocol.md for idiomatic patterns.

## Tool Integration
This skill provides a Clojure REPL for code evaluation.

## Available Tools
- clojure-eval: Evaluate Clojure expression in REPL
- clojure-load-file: Load and evaluate a file

## Usage
The AI uses clojure-eval to test hypotheses, then applies the 
clojure-protocol patterns to interpret results.
```

## Mementum Consolidation

Skills that are 90% protocol content should be consolidated into Mementum. This removes unnecessary indirection:

### Component Mapping

| Skill Component | Mementum Equivalent | Purpose |
|-----------------|---------------------|---------|
| `λ(observe)` | `store` | Persist observations |
| `λ(learn)` | `recall` | Retrieve relevant knowledge |
| `λ(evolve)` | `metabolize` | Update belief structures |
| `instincts/personal/` | `mementum/memories/` | Personal knowledge base |
| `instincts/library/` | `mementum/knowledge/` | General protocols and facts |
| Session state | `mementum/state.md` | Current context |
| Project facts | `mementum/knowledge/project-facts.md` | Project-specific knowledge |

### Before vs After

```yaml
# BEFORE: Indirection through skill wrapper
AGENTS.md
  → skills/
    → continuous-learning/
      → SKILL.md
        → procedures
        → memories

# AFTER: Direct protocol access
AGENTS.md
  → mementum/
    → knowledge/
      → learning-protocol.md  # Direct execution
    → memories/               # Personal knowledge
    → state.md               # Current context
```

## Decision Criteria

Use these rules to determine where content belongs:

| Condition | Action |
|-----------|--------|
| Skill contains only procedures/matrices | → Consolidate to `mementum/knowledge/{name}-protocol.md` |
| Skill has REPL/API/CLI dependencies | → Keep skill, extract protocol, add `depends:` frontmatter |
| Protocol applies to multiple skills | → Store in mementum, have skills reference it |
| Content is personal/contextual | → Store in `mementum/memories/` |
| Content is current session state | → Store in `mementum/state.md` |

## Implementation Checklist

When creating or reviewing a skill:

1. [ ] Does this skill require external systems (REPL, API, CLI)?
2. [ ] If yes → keep as Tool skill, create protocol file
3. [ ] If no → consolidate to `mementum/knowledge/{domain}-protocol.md`
4. [ ] Does the protocol have dependencies? → Move deps to tool skill
5. [ ] Can multiple tools use this protocol? → Ensure single protocol, multiple references

## Anti-Patterns to Avoid

- **Wrapper skills**: Skills that do nothing but wrap a protocol file
- **Duplicate procedures**: Same decision matrix in multiple skills
- **Deep indirection**: `AGENTS.md → skill → sub-skill → procedure` instead of direct access

## Related Topics

- [Mementum Architecture](/mementum/architecture) - System overview
- [Knowledge Base](/mementum/knowledge) - Protocol storage location
- [Memories](/mementum/memories) - Personal knowledge layer
- [State Management](/mementum/state) - Session context handling
- [Tool Skills Catalog](/skills/catalog) - Available tool skills
- [Protocol Patterns](/patterns/protocol) - Common protocol patterns

---

This architecture ensures that knowledge is stored at the appropriate layer—pure procedures in Mementum protocols, execution environments in Tool skills, enabling direct and efficient AI execution.