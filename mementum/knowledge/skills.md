---
title: Skill Architecture - Protocol vs Tool Skills
status: active
category: knowledge
tags: [skills, architecture, mementum, protocols, tools]
---

# Skill Architecture: Protocol vs Tool Skills

This document defines the architecture for organizing skills in the Mementum system, distinguishing between **Protocol Skills** (pure knowledge) and **Tool Skills** (external dependencies), and establishing when and how to consolidate skill content into reusable protocols.

---

## Overview

When building AI agents with persistent knowledge, it's essential to distinguish between two fundamental types of skills:

1. **Protocol Skills** - Pure procedural knowledge and decision matrices that can be executed directly
2. **Tool Skills** - Skills that require external systems (REPLs, APIs, CLIs) to function

Understanding this distinction prevents unnecessary indirection and enables knowledge reuse across multiple skills.

---

## Key Distinction

| Aspect | Protocol Skill | Tool Skill |
|--------|---------------|------------|
| **Definition** | Pure procedures, decision matrices, idiomatic patterns | Requires external system (REPL, API, CLI, scripts) |
| **Dependencies** | None - self-contained | External system required |
| **Storage Location** | `mementum/knowledge/{name}-protocol.md` | Keep in skills directory |
| **Execution Model** | AI reads protocol → executes directly | AI calls tool → gets result → applies protocol |
| **Examples** | learning, planning, sarcasmotron, tutor | clojure-expert, reddit, requesthunt, seo-geo |
| **Reusability** | High - can be shared across skills | Limited - tied to external system |

---

## Protocol Skills

### What Makes a Protocol

A protocol skill contains:

- **Procedures**: Step-by-step instructions for accomplishing tasks
- **Decision Matrices**: Conditional logic for choosing actions
- **Idiomatic Patterns**: Best practices for the domain
- **Examples**: Concrete demonstrations of the protocol in action

### Protocol File Structure

```yaml
---
title: {Domain} Protocol
status: active
category: knowledge
tags: [protocol, {domain}]
---

# {Domain} Protocol

## Overview

[Brief description of what this protocol covers]

## Decision Matrix

| Condition | Action |
|-----------|--------|
| When X | Do Y |
| When Z | Do W |

## Procedure: {Task Name}

1. Step one
2. Step two
3. Step three

## Examples

### Example 1: {Scenario}

[Detailed example]
```

### Example Protocol: Learning Protocol

```yaml
---
title: Learning Protocol
status: active
category: knowledge
tags: [protocol, learning, cognitive]
---

# Learning Protocol

## Overview

This protocol defines how to acquire, structure, and integrate new knowledge into the Mementum system.

## Decision Matrix: Knowledge Type Classification

| Input Type | Classification | Storage Location |
|------------|----------------|------------------|
| Factual project info | Project Fact | `mementum/knowledge/project-facts.md` |
| Personal preference/insight | Memory | `mementum/memories/personal/` |
| Reusable procedure/pattern | Protocol | `mementum/knowledge/{domain}-protocol.md` |
| Temporary session state | State | `mementum/state.md` |

## Procedure: Observe and Store

1. **Observe** - Capture the raw information
   - Note the source and timestamp
   - Identify key facts vs. context

2. **Classify** - Determine the knowledge type using the matrix above

3. **Store** - Write to the appropriate location
   - Project facts → append to `project-facts.md`
   - Personal memories → create new file in `memories/personal/`
   - Protocols → update or create `{domain}-protocol.md`

4. **Integrate** - Update relevant indices and cross-references

## Procedure: Recall and Apply

1. **Identify Need** - What knowledge is needed?
2. **Locate** - Find the relevant protocol or memory
3. **Recall** - Load the content into context
4. **Apply** - Execute the procedure or use the information

## Example: Learning New CLI Tool

```
Input: Learn how to use `gh` CLI for GitHub operations

Classification: Tool skill with protocol aspects
→ Store tool reference in skills/
→ Extract reusable protocol to mementum/knowledge/github-protocol.md

Protocol extracted:
- Authentication procedure
- Repository operations patterns
- Issue/PR management workflow
```
---

## Tool Skills

### What Makes a Tool Skill

A tool skill contains:

- **External Dependencies**: REPL, API, CLI, or scripts that must be present
- **Tool Invocation**: Commands to interact with the external system
- **Result Processing**: How to interpret tool output
- **Protocol Reference**: Links to the protocol that guides interpretation

### Tool Skill Structure

```yaml
---
title: {Tool Name} Skill
status: active
category: skill
tags: [skill, tool, {domain}]
depends: mementum/knowledge/{domain}-protocol.md
---

# {Tool Name} Skill

## Overview

[Brief description of what this tool does]

## External Dependencies

- {Dependency 1} - Required for X
- {Dependency 2} - Required for Y

## Tool Integration

### Available Tools

| Tool | Purpose | Command |
|------|---------|---------|
| {tool1} | {description} | `{command}` |
| {tool2} | {description} | `{command}` |

## Protocol Reference

See [mementum/knowledge/{domain}-protocol.md](mementum/knowledge/{domain}-protocol.md) for idiomatic patterns and procedures.

## Usage Examples

### Example 1: {Scenario}

```
Tool invocation: {command}
Result: {output}
Protocol application: {how protocol is applied}
```
```

### Example Tool Skill: Clojure Expert

```yaml
---
title: Clojure Expert Skill
status: active
category: skill
tags: [skill, tool, clojure, repl]
depends: mementum/knowledge/clojure-protocol.md
---

# Clojure Expert Skill

## Overview

Provides Clojure REPL integration for evaluating code, running tests, and exploring libraries.

## External Dependencies

- **Leiningen** (`lein`) - Build tool and REPL launcher
- **Clojure** - Runtime (included via Leiningen)
- **JVM** - Java virtual machine

## Tool Integration

### Available Tools

| Tool | Purpose | Command |
|------|---------|---------|
| `clojure/repl` | Start REPL session | `lein repl` |
| `clojure/run` | Run namespace | `lein run -m {namespace}` |
| `clojure/test` | Run tests | `lein test` |
| `clojure/deps` | Fetch dependencies | `clojure -M -m clojure.main` |

### Tool Invocation Examples

```bash
# Start a REPL
lein repl

# Run a specific namespace
lein run -m myapp.core

# Run tests
lein test

# Fetch deps and run
clojure -M -m myapp.core
```

## Protocol Reference

See [mementum/knowledge/clojure-protocol.md](mementum/knowledge/clojure-protocol.md) for:
- Clojure idiomatic patterns
- Data structure selection guide
- Threading macro usage
- Namespace organization best practices

## Usage Example: REPL-Driven Development

```
1. Start REPL: `lein repl`
2. Load code: `(use 'myapp.core)`
3. Protocol application: Follow clojure-protocol.md for idiomatic manipulation
4. Test: `(clojure.test/run-tests)`
5. Evolve: Apply learnings to protocol
```
---

## How They Work Together

### The Collaboration Model

```
┌─────────────────────────────────────────────────────────────┐
│                        AGENTS.md                            │
│                   (defines agent behavior)                  │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                   Tool Skill (e.g., clojure)               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ depends: mementum/knowledge/clojure-protocol.md     │   │
│  └─────────────────────────────────────────────────────┘   │
│                         │                                   │
│         ┌───────────────┴───────────────┐                  │
│         ▼                               ▼                  │
│  ┌──────────────────┐         ┌──────────────────────┐     │
│  │  External Tools  │         │  Protocol Reference  │     │
│  │  (REPL, CLI)     │         │  (clojure-protocol)  │     │
│  └──────────────────┘         └──────────────────────┘     │
└─────────────────────────┬───────────────────────────────────┘
                          │
          ┌───────────────┴───────────────┐
          ▼                               ▼
   ┌──────────────────┐        ┌──────────────────────┐
   │ Tool Execution    │        │ Protocol Execution    │
   │ (get raw result)  │        │ (apply patterns)      │
   └──────────────────┘        └──────────────────────┘
```

### Execution Flow

```python
# Pseudocode for skill execution

def execute_task(task, skill):
    if skill.has_external_deps:
        # Tool skill flow
        tool_result = skill.execute_tools(task)
        protocol = load_protocol(skill.depends)
        return protocol.apply(tool_result)
    else:
        # Protocol skill flow
        protocol = load_protocol(skill.path)
        return protocol.execute(task)
```

---

## Migration Patterns

### Pattern 1: Pure Procedure → Protocol

**Before:**
```yaml
---
title: Planning Skill
---
# Planning Skill

## Procedure
1. Define goal
2. Break into steps
3. Assign priorities
4. Execute
```

**After:**
```yaml
---
title: Planning Protocol
status: active
category: knowledge
tags: [protocol, planning]
---
# Planning Protocol

## Decision Matrix

| Goal Type | Approach |
|-----------|----------|
| Simple (1-3 steps) | Direct execution |
| Complex (4+ steps) | Break into sub-goals |

## Procedure: Plan and Execute

1. Define goal
2. Break into steps
3. Assign priorities
4. Execute
```

### Pattern 2: Tool Skill → Tool + Protocol

**Before:**
```yaml
---
title: SEO Geo Skill
---
# SEO Geo Skill

## Tools
- API calls to geo service

## Procedure
1. Query API
2. Parse response
3. Apply SEO patterns
```

**After:**

*File 1: `skills/seo-geo.md`*
```yaml
---
title: SEO Geo Skill
status: active
category: skill
tags: [skill, tool, seo]
depends: mementum/knowledge/seo-protocol.md
---

# SEO Geo Skill

## External Dependencies
- Geo API service

## Tool Integration
See [mementum/knowledge/seo-protocol.md](mementum/knowledge/seo-protocol.md)

## Usage
Tool provides geo data → apply seo-protocol.md patterns
```

*File 2: `mementum/knowledge/seo-protocol.md`*
```yaml
---
title: SEO Protocol
status: active
category: knowledge
tags: [protocol, seo]
---

# SEO Protocol

## Decision Matrix: Keyword Strategy

| Search Intent | Content Type | Keyword Focus |
|---------------|--------------|----------------|
| Informational | Blog post | Long-tail |
| Navigational | Brand page | Exact match |
| Transactional | Product page | Commercial |

## Procedure: Optimize Content

1. Analyze intent
2. Select keywords
3. Apply patterns
```

---

## Component Mapping

This table maps skill components to their Mementum equivalents:

| Skill Component | Mementum Equivalent | Notes |
|-----------------|---------------------|-------|
| `λ(observe)` | `store` | Capture and persist knowledge |
| `λ(learn)` | `recall` | Retrieve relevant knowledge |
| `λ(evolve)` | `metabolize` | Update and improve knowledge |
| `instincts/personal/` | `mementum/memories/` | Personal insights and preferences |
| `instincts/library/` | `mementum/knowledge/` | Reusable protocols and patterns |
| Session state | `mementum/state.md` | Temporary runtime information |
| Project facts | `mementum/knowledge/project-facts.md` | Factual project data |

---

## Architecture Comparison

### Before (Indirect)

```
AGENTS.md 
    → skills/ 
        → SKILL.md 
            → procedures 
                → memories
```

**Problems:**
- Multiple layers of indirection
- Knowledge scattered across skill wrappers
- Difficult to reuse procedures
- Hard to maintain consistency

### After (Direct)

```
AGENTS.md 
    → mementum/ 
        → knowledge/protocol.md 
            → direct execution
```

**Benefits:**
- Single source of truth for procedures
- Protocols are directly executable
- Easy to share across skills
- Clear separation of concerns

---

## Decision Guide: Which Type?

Use this decision tree to determine the appropriate type:

```
Does the skill require an external system?
│
├─► NO → Protocol Skill
│       Store in: mementum/knowledge/{name}-protocol.md
│
└─► YES → Does the skill add value beyond the external tool?
          │
          ├─► NO → Just use the tool directly
          │
          └─► YES → Tool Skill
                  Store tool in: skills/{name}.md
                  Extract protocol to: mementum/knowledge/{domain}-protocol.md
                  Add depends: to tool frontmatter
```

---

## When to Apply

### Consolidate to Protocol

- Skill contains only procedures and decision matrices
- No external dependencies required
- Content is reusable across multiple contexts
- Knowledge should be directly executable

### Keep as Tool Skill

- External system (REPL, API, CLI) required
- Tool provides unique capabilities
- Protocol exists for interpretation
- Skill manages tool orchestration

### Extract Protocol from Tool

- Tool skill contains procedural content beyond tool invocation
- Multiple tool skills share similar patterns
- Procedures could be reused without the tool
- Pattern: Create protocol, add `depends:` frontmatter

---

## Related Topics

- [Mementum Architecture](/mementum/architecture) - System structure and organization
- [Memory Types](/mementum/memory-types) - Classification of different memory types
- [Knowledge Management](/mementum/knowledge-management) - How to organize persistent knowledge
- [Skill Development](/skills/development) - Creating new skills for the agent
- [Protocol Design](/protocols/design) - Best practices for writing protocols

---

## Summary

The Protocol vs. Tool distinction provides a clear architecture for skill organization:

1. **Protocol Skills** are pure knowledge - procedures, decision matrices, patterns - stored in `mementum/knowledge/` and directly executable
2. **Tool Skills** require external systems, reference protocols, and orchestrate tool execution
3. **Migration** from indirect (skill → procedure → memory) to direct (mementum → protocol) eliminates unnecessary indirection
4. **Reuse** is enabled by extracting shared protocols that multiple tools can reference

This architecture ensures that knowledge remains accessible, maintainable, and reusable across the entire agent system.