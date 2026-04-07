---
title: Skills Architecture
status: active
category: knowledge
tags: [skills, protocols, architecture, mementum, tools, execution]
---

# Skills Architecture

## Overview

Skills are the execution layer of the Mementum system. They bridge **knowledge** (stored in `mementum/knowledge/`) with **action** (via tools and protocols). Understanding how to structure, categorize, and compose skills is essential for building effective autonomous agents.

## Two-Layer Architecture: Protocols vs Tools

The skills system operates on a two-layer model:

| Layer | Purpose | Storage | Dependencies |
|-------|---------|---------|--------------|
| **Protocol** | Pure procedures, decision matrices, idiomatic patterns | `mementum/knowledge/{domain}-protocol.md` | None |
| **Tool** | External integrations (REPL, API, CLI) | `skills/{domain}.md` | External systems |

### Protocol Layer

Protocols are **pure knowledge** — they describe *what* to do and *when*, without requiring external systems.

**Characteristics:**
- Decision matrices and conditional logic
- Step-by-step procedures
- Pattern catalogs and anti-patterns
- No side effects, no external calls

**Example Protocol Structure:**

```markdown
---
title: Learning Protocol
status: active
category: protocol
tags: [learning, observation, recall]
---

# Learning Protocol

## Observation Phase (λ observe)

When encountering new information:

1. **Classify** the information type:
   - Factual → `mementum/memories/facts/`
   - Procedural → `mementum/memories/procedures/`
   - Conceptual → `mementum/memories/concepts/`

2. **Extract** the core insight (one sentence)
3. **Store** with temporal tag `Δ: {confidence}`

## Recall Phase (λ learn)

When needing to retrieve knowledge:

1. Check `mementum/memories/` for relevant entries
2. Cross-reference with `mementum/knowledge/project-facts.md`
3. Apply temporal decay based on `Δ` value

## Evolution Phase (λ evolve)

When knowledge becomes stale:

1. Compare current state with `mementum/state.md`
2. Identify drift
3. Metabolize outdated entries
4. Update confidence scores
```

### Tool Layer

Tools are **external integrations** that require running systems.

**Characteristics:**
- REPL connections (Clojure, Python, Elisp)
- API calls (Reddit, GitHub, web search)
- CLI execution (bash scripts, compilers)
- Return structured data to the AI

**Example Tool Skill Structure:**

```markdown
---
title: Clojure Expert
depends: mementum/knowledge/clojure-protocol.md
category: skill
tags: [clojure, repl, lisp, functional]
---

# Clojure Expert

## Protocol Reference

See `mementum/knowledge/clojure-protocol.md` for idiomatic Clojure patterns,
data modeling conventions, and REPL-first methodology.

## Tool Integration

This skill provides the following tools:

| Tool | Purpose | Invocation |
|------|---------|------------|
| `clojure-eval` | Evaluate Clojure expressions | `(tool-call "Eval" :expression ...)` |
| `get-symbol-source` | Retrieve function source | `(tool-call "get_symbol_source" :name ...)` |
| `describe-symbol` | Get documentation | `(tool-call "describe_symbol" :name ...)` |

## REPL Workflow

1. Connect to running REPL
2. Evaluate expression via `clojure-eval`
3. Apply protocol patterns to results
4. Iterate until objective achieved

## Error Handling

When evaluation fails:
- Parse error type from message
- Apply troubleshooting protocol from `clojure-protocol.md`
- Retry with corrected expression
```

## Decision Matrix: Protocol vs Tool

Use this matrix to determine where content belongs:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CONTENT CLASSIFICATION                           │
├─────────────────────┬───────────────────────────────────────────────┤
│ Question            │ Answer                                         │
├─────────────────────┼───────────────────────────────────────────────┤
│ Does it need an     │ YES → Tool (keep in skills/)                  │
│ external system?    │ NO  → Protocol (move to mementum/knowledge/)  │
├─────────────────────┼───────────────────────────────────────────────┤
│ Is it pure logic/   │ YES → Protocol                                 │
│ decision trees?     │ NO  → Consider Tool if it generates output    │
├─────────────────────┼───────────────────────────────────────────────┤
│ Can AI execute it   │ YES → Protocol                                 │
│ without side effects?│ NO  → Tool                                     │
├─────────────────────┼───────────────────────────────────────────────┤
│ Does it return data │ YES → Tool                                     │
│ from external source?│ NO  → Protocol                                 │
└─────────────────────┴───────────────────────────────────────────────┘
```

## Concrete Examples

### Example 1: Planning Skill

**Before ( monolithic skill):**
```markdown
# Planning Skill
[150 lines of procedures, matrices, examples]
```

**After (split architecture):**

**`mementum/knowledge/planning-protocol.md`:**
```markdown
# Planning Protocol

## Phase Detection Matrix

| Input Signal | Planning Type | Duration |
|--------------|---------------|----------|
| "implement X" | Execution | Short |
| "design system" | Architectural | Medium |
| "explore options" | Strategic | Long |

## Execution Patterns

### Short-term (Execution)
1. Define concrete goal
2. List required steps
3. Execute sequentially
4. Validate results

### Medium-term (Architectural)
1. Understand constraints
2. Design component boundaries
3. Prototype interfaces
4. Iterate with feedback

### Long-term (Strategic)
1. Enumerate possibilities
2. Assess risks/rewards
3. Define milestones
4. Establish pivot criteria
```

**`skills/planning.md`:**
```markdown
---
title: Planning Skill
depends: mementum/knowledge/planning-protocol.md
---

# Planning Skill

Provides structured planning tools for the Planning Protocol.

## Tool Integration
This skill coordinates with other skills to execute plans:
- Project management (task tracking)
- Code execution (implementation)
- Research (information gathering)

## Usage
1. AI reads planning-protocol.md
2. Determines planning type from matrix
3. Applies appropriate pattern
4. Uses tools for execution
```

### Example 2: SEO-GEO Skill

**`mementum/knowledge/seo-geo-protocol.md`:**
```markdown
# SEO & GEO Protocol

## Keyword Research Patterns

| Search Type | Technique | Output |
|-------------|-----------|--------|
| Head terms | Google autocomplete | List of base queries |
| Long-tail | "people also ask" | Question patterns |
| LSI terms | Related searches | Semantic cluster |

## Schema Markup Templates

### Article Schema
```json
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "{{title}}",
  "author": { "@type": "Person", "name": "{{author}}" },
  "datePublished": "{{date}}",
  "keywords": ["{{kw1}}", "{{kw2}}"]
}
```

## AI Search Optimization

When optimizing for ChatGPT/Perplexity:
- Structure: Clear headings (H2, H3)
- Format: Numbered lists for steps
- Citations: Inline references to sources
- Length: 500-1500 words per section
```

**`skills/seo-geo.md`:**
```markdown
---
title: SEO-GEO Skill
depends: mementum/knowledge/seo-geo-protocol.md
tools: [WebSearch, WebFetch]
---

# SEO-GEO Skill

Provides web search and analysis tools for SEO/GEO optimization.

## Tools

| Tool | Purpose |
|------|---------|
| `WebSearch` | Keyword research, SERP analysis |
| `WebFetch` | Content extraction, competitor analysis |

## Workflow
1. Run keyword research (WebSearch)
2. Analyze competitors (WebFetch)
3. Apply protocol patterns
4. Generate optimized content
```

## The Mementum Equivalence Map

Many skill concepts map directly to Mementum operations:

| Skill Concept | Mementum Equivalent | Description |
|---------------|---------------------|-------------|
| `λ(observe)` | `store` | Capture new information |
| `λ(learn)` | `recall` | Retrieve relevant knowledge |
| `λ(evolve)` | `metabolize` | Update stale information |
| `instincts/personal/` | `mementum/memories/` | Personal knowledge base |
| `instincts/library/` | `mementum/knowledge/` | Shared protocols |
| Session state | `mementum/state.md` | Current context |
| Project facts | `mementum/knowledge/project-facts.md` | Project metadata |

## Architecture Evolution

### Before: Indirection Layer
```
AGENTS.md → skills/ → SKILL.md → procedures → memories
           ↑
           Unnecessary wrapper adds complexity
```

### After: Direct Execution
```
AGENTS.md → mementum/ → knowledge/{domain}-protocol.md → direct execution
           ↑
           Protocol IS the knowledge
```

## When to Apply Each Pattern

| Scenario | Action |
|----------|--------|
| Skill with only procedures/matrices | Consolidate to `mementum/knowledge/{name}-protocol.md` |
| Skill with REPL/API/scripts | Keep skill, extract protocol, add `depends:` frontmatter |
| Multiple skills sharing patterns | Create shared protocol, reference via `depends:` |
| Skills with state | Use `mementum/state.md` |
| Skills with patterns/insights | Use `mementum/memories/` |

## Frontmatter Reference

### Protocol Frontmatter
```yaml
---
title: {Protocol Name}
status: active
category: protocol
tags: [domain, type]
---
```

### Tool Skill Frontmatter
```yaml
---
title: {Skill Name}
depends: mementum/knowledge/{domain}-protocol.md
category: skill
tags: [domain, tools]
---
```

## Best Practices

1. **Extract, Don't Duplicate**: If a skill is 90% protocol content, extract it
2. **Single Responsibility**: Protocols handle logic, tools handle execution
3. **Explicit Dependencies**: Always declare `depends:` when referencing protocols
4. **Version Together**: When updating a protocol, update all referencing skills
5. **Test the Protocol**: Verify protocol patterns work independently of tools

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Fat skills | Indirection without value | Extract protocol |
| Duplicate logic | Maintenance burden | Centralize in protocol |
| Protocol pollution | Tools knowledge in protocol | Keep pure procedures |
| Circular dependencies | Confusing relationships | Unidirectional flow |

## Related

- [mementum/knowledge/mementum-overview.md](mementum-overview) — Mementum system architecture
- [mementum/memories/](memories) — Personal knowledge storage
- [mementum/state.md](state) — Session and project state
- [mementum/knowledge/project-facts.md](project-facts) — Project metadata
