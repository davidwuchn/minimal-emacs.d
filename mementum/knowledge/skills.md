---
title: Skills Architecture
status: active
category: knowledge
tags: [skills, protocols, tools, mementum, architecture]
---

# Skills Architecture

## Overview

This page defines the architectural pattern for organizing skills in the Mementum system. The core principle: **distinguish between protocol knowledge (which belongs in Mementum) and tool integrations (which remain as skills)**.

This separation eliminates unnecessary indirection while maintaining the ability to integrate with external systems like REPLs, APIs, and CLIs.

## The Two Types of Skills

Understanding this distinction is fundamental to building maintainable, reusable knowledge structures.

### Protocol Skills

Protocol skills contain **pure procedures and decision matrices** with no external dependencies. They define *how* to think and act, not *with what tools*.

**Characteristics:**
- No external system calls (no REPL, API, CLI)
- Pure decision trees and procedural logic
- Human-readable patterns and examples
- Directly executable by the AI after reading

**Examples:**
- `learning` — how to learn new topics effectively
- `planning` — decision matrix for project planning
- `tutor` — instructional methodology
- `sarcasmotron` — tone/communication style

### Tool Skills

Tool skills provide **integration with external systems**. They supply capabilities (REPL access, API calls, CLI execution) and reference protocols for applying those capabilities.

**Characteristics:**
- Requires external system (REPL, API, scripts)
- Provides tools that the AI can invoke
- References protocol for application logic
- Handles data transformation and error handling

**Examples:**
- `clojure-expert` — REPL access for Clojure code
- `reddit` — Reddit API integration
- `requesthunt` — HTTP request tool
- `seo-geo` — SEO API integration

## Comparison Matrix

| Aspect | Protocol Skill | Tool Skill |
|--------|---------------|------------|
| **External Dependencies** | None | REPL, API, CLI, or scripts |
| **Storage Location** | `mementum/knowledge/{domain}-protocol.md` | `skills/{domain}/SKILL.md` |
| **Frontmatter** | `type: protocol` | `depends: mementum/knowledge/{domain}-protocol.md` |
| **Content** | Procedures, matrices, examples | Tool definitions, API specs, error handling |
| **AI Interaction** | Read → Execute | Call tool → Apply protocol |
| **Reusability** | Shared across multiple tool skills | Domain-specific |

## How They Work Together

The architecture creates a clean separation of concerns:

```
┌─────────────────────────────────────────────────────────────────┐
│                         AI Session                               │
│                                                                  │
│  1. orient() → Reads mementum/knowledge/{domain}-protocol.md    │
│                                                                  │
│  2. For tool operations:                                         │
│     ├─→ Tool Skill provides REPL/API/CLI access                  │
│     ├─→ AI calls tool → gets result                              │
│     └─→ AI applies protocol procedures to result                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

Protocol Skill (mementum/knowledge/):
  ## Decision Matrix
  ## Procedures  
  ## Examples
  ## Patterns
  
Tool Skill (skills/):
  ## Protocol Reference
  ## Tool Definitions
  ## Integration Code
  ## Error Handling
```

## Mementum Mapping

Protocol content maps directly to Mementum operations and locations:

| Protocol Component | Mementum Equivalent | Purpose |
|--------------------|---------------------|---------|
| Observation procedures | `store` operation | Capture new information |
| Learning patterns | `recall` operation | Access stored knowledge |
| Evolution logic | `metabolize` operation | Refine and update |
| `instincts/personal/` | `mementum/memories/` | Personal context |
| `instincts/library/` | `mementum/knowledge/` | Shared knowledge |
| Session state | `mementum/state.md` | Current context |
| Project facts | `mementum/knowledge/project-facts.md` | Domain knowledge |

## Architecture Evolution

### Before (Indirection Layer)

```
AGENTS.md → skills/ → SKILL.md → procedures → memories
```

Problems with this approach:
- Skills became thin wrappers around protocol content
- Indirection without value
- Duplicate knowledge structures
- Unclear ownership of patterns

### After (Direct Protocol Access)

```
AGENTS.md → mementum/ → knowledge/{domain}-protocol.md → direct execution
```

Benefits:
- Protocol content lives where it's used
- Clear separation of concerns
- Reduced duplication
- Protocol can be shared across multiple tools

## Pattern Library

### Pattern 1: Protocol Frontmatter

```yaml
---
title: {domain}-protocol
type: protocol
version: 1.0
created: {timestamp}
---

## Purpose
Brief description of what this protocol defines.

## When to Use
- Context where this protocol applies
- Prerequisites before execution
```

### Pattern 2: Tool Skill Frontmatter with Dependency

```yaml
---
title: {domain}-expert
type: tool-skill
version: 1.0
depends:
  - mementum/knowledge/{domain}-protocol.md
tools:
  - name: evaluate
    description: Execute code in REPL
    returns: execution result
---

## Protocol Reference
See [mementum/knowledge/{domain}-protocol.md](mementum/knowledge/{domain}-protocol.md) for idiomatic patterns and procedures.

## Tool Integration
This skill provides REPL access for executing code according to the protocol.
```

### Pattern 3: Protocol Decision Matrix

```markdown
## Decision Matrix: {Scenario}

| Condition | Action | Output |
|-----------|--------|--------|
| `input is primitive` | apply-basic-transformation | transformed primitive |
| `input is collection` | iterate-and-transform | collection of transformed |
| `collection is large` | batch-process | batch results |
| `error encountered` | apply-error-protocol | error report |
```

### Pattern 4: Tool Skill Error Handling

```markdown
## Error Handling

| Error Type | Protocol Action | User Message |
|------------|-----------------|--------------|
| `connection-failed` | retry-3x | "Unable to connect. Retrying..." |
| `timeout` | backoff-then-retry | "Request timed out. Retrying with backoff..." |
| `auth-failed` | prompt-reauth | "Authentication required." |
| `rate-limited` | wait-then-retry | "Rate limited. Waiting {n} seconds..." |
```

## Decision Framework

Use this framework to determine where content belongs:

```
START: Is this skill about procedures/decisions?
├─ NO → Does it integrate external systems?
│        ├─ YES → Tool Skill (skills/)
│        └─ NO → General documentation
└─ YES → Does it require external dependencies?
         ├─ YES → Extract protocol, keep tool wrapper
         │        - Protocol → mementum/knowledge/{domain}-protocol.md
         │        - Tool → skills/{domain}/SKILL.md with depends
         └─ NO → Protocol only
                  → mementum/knowledge/{domain}-protocol.md
```

### Decision Tree Implementation

```markdown
## Content Classification

1. **Is there external system access?**
   - YES → Tool Skill with `depends:` frontmatter
   
2. **Is there only procedures/matrices?**
   - YES → Protocol in mementum/knowledge/
   
3. **Can multiple tools use this knowledge?**
   - YES → Extract to shared protocol
   
4. **Is this skill stateful?**
   - YES → Use mementum/state.md for state
```

## Migration Guide

### Converting an Existing Skill to Protocol + Tool

**Before:**
```markdown
# skill/example/SKILL.md

## Procedures
...procedural content...

## Tools
...tool definitions...

## State
...state management...
```

**After:**

1. Create `mementum/knowledge/example-protocol.md`:
```markdown
---
title: example-protocol
type: protocol
---

## Procedures
...moved procedural content...

## Decision Matrix
...moved decision content...
```

2. Update `skill/example/SKILL.md`:
```markdown
---
title: example
type: tool-skill
depends:
  - mementum/knowledge/example-protocol.md
---

## Protocol Reference
See [example-protocol.md](mementum/knowledge/example-protocol.md).

## Tool Integration
...tool definitions only...
```

### Migration Checklist

- [ ] Identify pure protocol content
- [ ] Create `mementum/knowledge/{domain}-protocol.md`
- [ ] Move procedures, matrices, examples to protocol
- [ ] Update original skill with `depends:` frontmatter
- [ ] Add protocol reference section to skill
- [ ] Verify no duplicate content remains
- [ ] Update any skills that reference old location

## Protocol Structure Template

```markdown
---
title: {domain}-protocol
type: protocol
version: 1.0
prerequisites:
  - skill: prerequisite-skill
  - knowledge: foundational-concept
---

# {Domain} Protocol

## Purpose
What this protocol accomplishes and when to use it.

## Prerequisites
- Required knowledge or skills before application
- Dependencies on other protocols

## Procedures

### Procedure 1: {Name}
**When:** Trigger conditions for this procedure

**Steps:**
1. Step one
2. Step two
3. Step three

**Output:** Expected result

## Decision Matrix

| Condition | Action | Notes |
|-----------|--------|-------|
| ... | ... | ... |

## Examples

### Example 1: {Scenario}
**Input:** ...
**Expected Output:** ...
**Reasoning:** ...

## Anti-Patterns

### What NOT to Do
- Common mistakes
- Edge cases to avoid

## Related Protocols
- [Related Protocol 1](mementum/knowledge/related-protocol.md)
- [Related Protocol 2](mementum/knowledge/related-protocol.md)
```

## Common Mistakes

### Mistake 1: Protocol Tool Confusion
**Wrong:** Embedding tool-specific logic in protocols
```markdown
## DO NOT DO THIS in protocol
curl -X POST http://api.example.com/execute
```

**Right:** Protocols define *how*, tools define *with what*
```markdown
## In protocol
Apply the configured transformation to input.

## In tool skill
curl -X POST http://api.example.com/transform \
  -d "input={input}"
```

### Mistake 2: Keeping Empty Wrappers
**Wrong:** Skill that only references protocol with no tool additions
```yaml
---
depends: mementum/knowledge/example-protocol.md
---
## Protocol Reference
See [example-protocol.md](mementum/knowledge/example-protocol.md).
```

**Right:** Either the skill adds value (tool integration) or it should not exist—use the protocol directly.

### Mistake 3: Protocol Bloat
**Wrong:** Including unrelated procedures in a single protocol
```yaml
title: everything-protocol
```

**Right:** Single-responsibility protocols that can be composed
```yaml
title: {specific-domain}-{specific-purpose}-protocol
```

## Best Practices

1. **Single Responsibility**: Each protocol should define one domain or one aspect of execution
2. **Dependency Declaration**: Always declare dependencies in frontmatter
3. **Concrete Examples**: Every procedure needs at least one worked example
4. **Version Control**: Protocols evolve; maintain version numbers for compatibility
5. **Shared Protocols**: Extract common patterns into shared protocols that multiple tools reference
6. **No Duplication**: If a pattern appears in multiple places, extract to shared protocol

## Implementation Commands

```bash
# Create protocol structure
mkdir -p mementum/knowledge
touch mementum/knowledge/{domain}-protocol.md

# Create tool skill with dependency
mkdir -p skills/{domain}
cat > skills/{domain}/SKILL.md << 'EOF'
---
title: {domain}-expert
type: tool-skill
depends:
  - mementum/knowledge/{domain}-protocol.md
---
EOF

# Validate frontmatter consistency
grep -r "depends:" skills/ | while read file; do
  dep=$(echo "$file" | sed 's/.*depends: //')
  [ -f "$dep" ] || echo "Missing: $dep referenced in $file"
done
```

## Related

- [Mementum System Overview](mementum/overview.md)
- [Tool Integration Patterns](mementum/knowledge/tool-integration-patterns.md)
- [State Management](mementum/state.md)
- [Memory Architecture](mementum/memories/architecture.md)
- [Learning Protocol](mementum/knowledge/learning-protocol.md)
- [Planning Protocol](mementum/knowledge/planning-protocol.md)
```