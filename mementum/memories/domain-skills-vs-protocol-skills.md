---
title: Domain-Specific Skills vs Protocol Skills
φ: 0.9
e: distinguish-skill-types
λ: when.consolidating.skills
Δ: 0.05
evidence: 1
---

💡 Two types of skills: **Protocol** (consolidate to mementum) and **Tool** (keep as skill with external deps).

## Key Distinction

| Type | Example | Has External Deps? | Action |
|------|---------|-------------------|--------|
| Protocol | learning, planning, sarcasmotron, tutor | No | → `mementum/knowledge/{name}-protocol.md` |
| Tool | clojure-expert, reddit, requesthunt, seo-geo | Yes (REPL, API, CLI) | → Keep as skill, reference protocol |

## How They Work Together

```
Protocol skill:
  - Pure procedures and decision matrices
  - AI reads protocol → executes
  - No external dependencies

Tool skill:
  - Requires external system (REPL, API, scripts)
  - Skill provides tools, references protocol
  - AI calls tool → gets result → applies protocol
```

## Pattern

```
Tool Skill Structure:
---
depends: mementum/knowledge/{domain}-protocol.md
---

## Protocol Reference
See mementum/knowledge/{domain}-protocol.md for idiomatic patterns.

## Tool Integration
This skill provides REPL/API tools for the protocol.
```

## When to Apply

- Skill with only procedures/matrices → consolidate to `mementum/knowledge/{name}-protocol.md`
- Skill with REPL/API/scripts → keep skill, extract protocol, add `depends:` frontmatter
- Protocol can be shared across multiple skills