---
title: Skill Architecture - Protocols vs Tools
status: active
category: knowledge
tags: [skills, protocols, mementum, architecture, tooling]
---

# Skill Architecture: Protocols vs Tools

This document establishes the architectural pattern for organizing skills in the mementum system. It defines how to distinguish between **Protocol Skills** and **Tool Skills**, when to consolidate protocol content into mementum, and how these components interact.

## Overview

The skill architecture follows a fundamental insight: many skills contain mostly procedural content that belongs directly in mementum knowledge pages. Rather than wrapping protocols in skill wrappers with unnecessary indirection, the system separates pure procedures (protocols) from skills that require external dependencies (tools).

## Two Types of Skills

| Type | Definition | External Dependencies | Storage Location |
|------|------------|----------------------|------------------|
| **Protocol** | Pure procedures, decision matrices, and execution patterns | None | `mementum/knowledge/{name}-protocol.md` |
| **Tool** | Skills that interact with external systems (REPLs, APIs, CLIs) | Yes (requires external system) | `skills/{name}/` |

### Protocol Skills

Protocol skills contain only procedural knowledge that the AI can read and execute directly. They have no external dependencies.

**Examples:**
- `learning-protocol.md` - How to learn and consolidate information
- `planning-protocol.md` - Decision matrices for planning operations
- `tutor-protocol.md` - Teaching and explanation patterns
- `sarcasmotron-protocol.md` - Humor generation patterns

### Tool Skills

Tool skills require external systems to function. They provide the interface between mementum and external tools.

**Examples:**
- `clojure-expert` - Requires Clojure REPL
- `reddit` - Requires Reddit API
- `requesthunt` - Requires HTTP client
- `seo-geo` - Requires CLI tools

## The Mapping: Skills to Mementum

When consolidating skills, use this mapping table:

| Skill Component | Mementum Equivalent | Purpose |
|-----------------|---------------------|---------|
| `λ(observe)` | `store` | Capture new information |
| `λ(learn)` | `recall` | Retrieve and apply knowledge |
| `λ(evolve)` | `metabolize` | Update and refine patterns |
| `instincts/personal/` | `mementum/memories/` | Personal experience memory |
| `instincts/library/` | `mementum/knowledge/` | Learned patterns and protocols |
| Session state | `mementum/state.md` | Current working context |
| Project facts | `mementum/knowledge/project-facts.md` | Project-specific information |

## Architecture Patterns

### Before: With Skill Wrappers

```
AGENTS.md
  └── skills/
        └── continuous-learning/
              └── SKILL.md
                    ├── procedures: 90%
                    └── memories: 10%
```

**Problem:** The skill wrapper adds indirection. 90% of the content is protocol that could be read directly.

### After: Consolidated Protocol

```
AGENTS.md
  └── mementum/
        └── knowledge/
              └── learning-protocol.md  ← Pure protocol content
```

**Solution:** Protocol content lives directly in mementum. AI reads via `orient()` and executes immediately.

### Hybrid: Tool + Protocol

For skills with external dependencies:

```
AGENTS.md
  ├── mementum/
  │     └── knowledge/
  │           └── clojure-protocol.md  ← Pure patterns
  └── skills/
        └── clojure-expert/             ← Tool wrapper
              ├── depends: mementum/knowledge/clojure-protocol.md
              └── tools: REPL integration
```

## Tool Skill Structure

When creating a tool skill that references a protocol, use this structure:

```yaml
---
title: Clojure Expert
status: active
category: skill
tags: [clojure, repl, tool]
depends: mementum/knowledge/clojure-protocol.md
---

# Clojure Expert

## Protocol Reference

See [mementum/knowledge/clojure-protocol.md](../clojure-protocol.md) for idiomatic patterns and decision matrices.

## Tool Integration

This skill provides REPL tools for executing Clojure code.

### Available Tools

| Tool | Purpose | Command |
|------|---------|---------|
| `repl/eval` | Evaluate Clojure expression | `(clojure (code))` |
| `repl/load-file` | Load and execute file | `(load-file "path")` |

### Usage Pattern

```python
# 1. Read protocol for patterns
protocol = read("mementum/knowledge/clojure-protocol.md")

# 2. Use tool to get result
result = repl.eval("(map inc [1 2 3])")

# 3. Apply protocol to result
apply_pattern(protocol, result)
```

## Decision Matrix: Which Type?

Use this matrix to determine how to store skill content:

```
DECISION TREE:
│
├── Does the content have external dependencies?
│   │
│   ├── NO → Protocol skill
│   │       → Store in mementum/knowledge/{name}-protocol.md
│   │
│   └── YES → Does it contain procedural patterns?
│               │
│               ├── YES → Extract protocol, keep tool
│               │       → Protocol: mementum/knowledge/{name}-protocol.md
│               │       → Tool: skills/{name}/
│               │
│               └── NO → Keep entirely as tool skill
│                       → No protocol extraction needed
```

## Implementation Commands

### Creating a Protocol

```bash
# Create new protocol in mementum
touch mementum/knowledge/{name}-protocol.md

# Add frontmatter
cat > mementum/knowledge/{name}-protocol.md << 'EOF'
---
title: {Name} Protocol
status: active
category: knowledge
tags: [protocol, {domain}]
---

# {Name} Protocol

## Overview

[Description of what this protocol governs]

## Decision Matrix

| Context | Condition | Action |
|---------|-----------|--------|
| ... | ... | ... |

## Procedures

### Procedure 1: [Name]

[Step-by-step procedure]
EOF
```

### Linking Tool to Protocol

```yaml
# In tool skill frontmatter
depends:
  - mementum/knowledge/{protocol-name}.md
```

### Verifying Dependencies

```bash
# Check all protocol dependencies
grep -r "depends:" skills/*/skill.md | sed 's/depends: //'

# Find orphaned protocols (no tool references)
ls mementum/knowledge/*-protocol.md | while read p; do
  name=$(basename $p -protocol.md)
  grep -rq "$name-protocol" skills/ || echo "Orphaned: $p"
done
```

## Protocol Content Example

Here is a concrete example of what protocol content looks like:

```markdown
---
title: Planning Protocol
status: active
category: knowledge
tags: [protocol, planning, decision]
---

# Planning Protocol

## Decision Matrix

| Context | Condition | Action |
|---------|-----------|--------|
| New task | `λ(task) < λ(threshold)` | Break into subtasks |
| Complex task | `subtasks > 5` | Create dependency graph |
| Blocked task | `dependency.pending` | Switch to unblocked task |
| Task complete | `λ(outcome) > 0.8` | Mark complete, notify |
| Task failed | `λ(outcome) < 0.3` | Log failure, retry or escalate |

## Procedures

### Procedure: Plan Decomposition

1. Identify the goal state `G`
2. Measure current state `C`
3. Compute delta `Δ = G - C`
4. If `|Δ| > threshold`:
   - Decompose into subtasks `{t1, t2, ..., tn}`
   - For each subtask, compute `λ(ti)`
   - Order by `λ(ti)` descending
5. Return ordered task list

### Procedure: Dependency Resolution

1. Build graph `G(V, E)` where V = tasks, E = dependencies
2. Topological sort → ordered list
3. Identify critical path (longest path)
4. Return execution order with critical path highlighted
```

## When to Apply This Pattern

### Consolidate to Protocol

Apply when:
- Skill with only procedures/matrices exists
- Content is 90%+ protocol that maps to mementum operations
- No external dependencies required
- Pattern can be shared across multiple skills

### Keep as Tool Skill

Apply when:
- Skill requires REPL, API, or CLI interaction
- External system state affects execution
- Tool provides necessary data that protocol consumes

### Extract Protocol from Tool

Apply when:
- Existing tool skill contains procedural patterns
- Multiple tools could share the same protocol
- Protocol patterns are reusable independently

## Anti-Patterns to Avoid

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Wrapper skill | Indirection without value | Store protocol directly in mementum |
| Duplicate protocols | Same patterns in multiple skills | Single source of truth in mementum |
| Protocol with hidden deps | Claims no deps but has them | Audit thoroughly, mark dependencies |
| Tool without protocol | No reusable patterns | Extract protocol if patterns exist |

## Related

- [Mementum Architecture](mementum-architecture.md) - System structure
- [Memory Types](memory-types.md) - Distinction between memories and knowledge
- [Skill Categories](skill-categories.md) - Full skill taxonomy
- [State Management](state-management.md) - Managing session state in mementum
- [Tool Integration](tool-integration.md) - Connecting external tools to protocols

---

*This knowledge page defines the canonical pattern for skill organization. All skill architecture decisions should reference this document.*