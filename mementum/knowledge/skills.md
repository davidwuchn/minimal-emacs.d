---
title: Skills Architecture - Protocols vs Tools Consolidation
status: active
category: knowledge
tags: [skills, protocols, mementum, architecture, consolidation]
---

# Skills Architecture: Protocols vs Tools Consolidation

## Overview

This document describes the architectural pattern for organizing skills within the Mementum system. The core principle is that **skills should consolidate their protocol content into Mementum knowledge pages**, eliminating thin wrappers and enabling direct execution by AI systems.

## The Two-Skill Model

Understanding the distinction between **Protocol Skills** and **Tool Skills** is fundamental to proper skill architecture.

### Protocol Skills

Protocol skills contain pure procedures, decision matrices, and idiomatic patterns that the AI can read and execute directly. They have no external dependencies.

**Characteristics:**
- Pure procedures and decision matrices
- AI reads protocol → executes directly
- No external dependencies (REPL, API, CLI)
- Stored in `mementum/knowledge/{domain}-protocol.md`

**Examples:**
- `learning` - how to learn effectively
- `planning` - planning procedures and decision trees
- `tutor` - teaching methodologies
- `sarcasmotron` - conversational patterns

### Tool Skills

Tool skills require external systems to function. They provide interfaces to REPLs, APIs, CLIs, or other external tools.

**Characteristics:**
- Requires external system (REPL, API, scripts)
- Skill provides tools, references protocol
- AI calls tool → gets result → applies protocol
- Kept as skill with `depends:` frontmatter

**Examples:**
- `clojure-expert` - requires Clojure REPL
- `reddit` - requires Reddit API
- `requesthunt` - requires HTTP client
- `seo-geo` - requires external SEO tools

## Comparison Table

| Aspect | Protocol Skill | Tool Skill |
|--------|----------------|------------|
| External Deps | None | REPL, API, CLI |
| Storage | `mementum/knowledge/{name}-protocol.md` | `skills/` directory |
| Execution | Direct from protocol | Tool call → protocol application |
| Reusability | Can be shared across multiple tools | Tied to external system |
| Frontmatter | Standard knowledge frontmatter | `depends:` pointing to protocol |

## Skill-to-Mementum Mapping

When consolidating skills, map their components to Mementum equivalents:

| Skill Component | Mementum Equivalent | Description |
|-----------------|---------------------|-------------|
| `λ(observe)` | `store` | Storing observations and data |
| `λ(learn)` | `recall` | Retrieving learned patterns |
| `λ(evolve)` | `metabolize` | Updating and evolving knowledge |
| `instincts/personal/` | `mementum/memories/` | Personal context and history |
| `instincts/library/` | `mementum/knowledge/` | General knowledge and patterns |
| Session state | `mementum/state.md` | Current session context |
| Project facts | `mementum/knowledge/project-facts.md` | Project-specific information |

## Architecture Patterns

### Pattern 1: Protocol Consolidation

For skills that are 90% protocol/procedure content, consolidate directly into Mementum:

```
Before:  AGENTS.md → skills/ → SKILL.md → procedures → memories
After:   AGENTS.md → mementum/ → knowledge/protocol.md → direct execution
```

**Example Protocol Frontmatter:**

```yaml
---
title: Planning Protocol
status: active
category: protocol
tags: [planning, protocol, procedures]
depends: []
---

# Planning Protocol

## Overview
[Protocol description]

## Decision Matrix
[Procedures and conditions]

## Execution Flow
[Step-by-step instructions]
```

### Pattern 2: Tool Skill with Protocol Reference

For skills requiring external dependencies, keep the skill but extract the protocol:

```yaml
---
title: Clojure Expert
status: active
category: skill
tags: [clojure, tool, repl]
depends: mementum/knowledge/clojure-protocol.md
---

# Clojure Expert

## Protocol Reference
See [mementum/knowledge/clojure-protocol.md](clojure-protocol.md) for idiomatic patterns and procedures.

## Tool Integration
This skill provides a REPL interface for executing Clojure code according to the protocol.

### Available Tools
- `clojure-eval`: Evaluate Clojure expressions
- `clojure-load-file`: Load and execute files
- `clojure-test`: Run test suites
```

### Pattern 3: Protocol Sharing

A single protocol can be shared across multiple tool skills:

```
mementum/knowledge/
├── learning-protocol.md      (shared by all learning tools)
├── planning-protocol.md      (shared by all planning tools)
├── debugging-protocol.md     (shared by clojure-expert, python-expert, etc.)

skills/
├── clojure-expert/           (depends: debugging-protocol.md)
├── python-expert/            (depends: debugging-protocol.md)
├── rust-expert/              (depends: debugging-protocol.md)
```

## When to Apply Each Pattern

### Consolidate to Protocol

Apply when:
- Skill contains only procedures/matrices
- Skill is 90%+ protocol content
- No external dependencies required
- Pattern can be reused across tools

**Action:** Migrate to `mementum/knowledge/{name}-protocol.md`

### Keep as Tool Skill

Apply when:
- Skill requires REPL, API, or CLI access
- External system interaction is necessary
- Tool provides specific capabilities beyond protocol

**Action:** Keep in `skills/`, extract protocol to `mementum/knowledge/`, add `depends:` frontmatter

### Use State Files

Apply when:
- Skill maintains session state
- Context needs to persist across interactions
- Project-specific facts need tracking

**Action:** Use `mementum/state.md` and `mementum/knowledge/project-facts.md`

## Implementation Examples

### Example 1: Creating a New Protocol

```bash
# Create protocol directory
mkdir -p mementum/knowledge/planning

# Create protocol file
cat > mementum/knowledge/planning-protocol.md << 'EOF'
---
title: Planning Protocol
status: active
category: protocol
tags: [planning, procedures, decision-matrix]
depends: []
---

# Planning Protocol

## Goal Decomposition Procedure

1. **Identify the end state** - What does success look like?
2. **Working backward** - What must be true before the end state?
3. **Identify dependencies** - What must be completed first?
4. **Estimate complexity** - Break down into smallest actionable units

## Decision Matrix

| Context | Action |
|---------|--------|
| Unclear requirements | Request clarification before planning |
| High uncertainty | Create exploratory spikes |
| Large scope | Decompose into milestones |
| Many dependencies | Create dependency graph |
EOF
```

### Example 2: Converting Tool Skill to Protocol Reference

```yaml
# skills/seo-geo/skill.yaml - Before
---
name: seo-geo
description: Geo-specific SEO analysis
---

# All procedures were here - WRONG

# skills/seo-geo/skill.yaml - After
---
name: seo-geo
description: Geo-specific SEO analysis
depends: mementum/knowledge/seo-protocol.md
---

# seo-geo

## Tool Capabilities
- Geo-rank tracking
- Local SERP analysis
- Region-specific keyword research

## Protocol Reference
This skill executes [seo-protocol.md](mementum/knowledge/seo-protocol.md) procedures against geo-specific data.

## Usage
1. Provide target geo (country, region, city)
2. Skill queries geo-db for rankings
3. Applies seo-protocol analysis procedures
4. Returns geo-optimized recommendations
```

### Example 3: State Management

```yaml
# mementum/state.md
---
title: Session State
last_updated: 2025-01-13
---

# Current Session

## Active Context
- Task: Implementing skills architecture
- Phase: Documentation
- Depth: 2

## Recent Interactions
- planning-protocol: invoked at 10:30
- clojure-eval: executed at 10:32

## Variables
| Key | Value |
|-----|-------|
| current_project | mementum-v2 |
| active_skill | skills-architecture |
```

## Decision Flowchart

```
Skill Exists
     │
     ▼
Has External Dependencies?
     │
    ├─No────────────────────┤Yes
     │                      │
     ▼                      ▼
Protocol Skill?       Tool Skill?
     │                      │
    ├─Yes──────────┐No     │
     │             │       │
     ▼             ▼       ▼
Consolidate    Keep in    Keep skill
to mementum/   skills/    Extract protocol
knowledge/              to mementum/
                         Add depends:
```

## Anti-Patterns to Avoid

### Thin Wrapper Anti-Pattern

**Bad:**
```yaml
# skills/learning/skill.yaml
---
name: learning
---

# This skill delegates to mementum/knowledge/learning.md

## Procedures
See mementum/knowledge/learning.md
```

**Why it's bad:** Adds indirection without value. Just use the protocol directly.

### Protocol/Tool Mixing

**Bad:**
```yaml
# skills/planner/skill.yaml
---
name: planner
---

# Contains BOTH procedures AND REPL calls
# No clear separation
```

**Why it's bad:** Violates separation of concerns. Protocol should be pure; tool should reference it.

## Related Topics

- [Mementum Architecture](/mementum/architecture) - System overview
- [Knowledge Organization](/mementum/knowledge/organization) - How knowledge is structured
- [Skill Development](/skills/development) - Creating new skills
- [State Management](/mementum/state-management) - Handling session state
- [Tool Integration](/skills/tool-integration) - Connecting external tools

---

## Changelog

| Date | Change |
|------|--------|
| 2025-01-13 | Initial document creation |
| 2025-01-13 | Added decision flowchart |
| 2025-01-13 | Included implementation examples |
| 2025-01-13 | Added anti-patterns section |