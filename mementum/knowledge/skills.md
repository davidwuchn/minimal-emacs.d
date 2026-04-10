---
title: skills
status: open
---

Synthesized from 3 memories.

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

---
title: Skills Consolidate into Mementum Protocols
φ: 0.85
e: consolidate-skills-to-mementum
λ: when.skill.exists
Δ: 0.05
evidence: 1
---

💡 Skills don't need thin wrappers. Protocol content belongs in `mementum/knowledge/{domain}-protocol.md`.

## What We Learned

Skills (continuous-learning, planning) were 90% protocol/procedure content that maps directly to Mementum operations:

| Skill Component | Mementum Equivalent |
|-----------------|---------------------|
| `λ(observe)` | `store` |
| `λ(learn)` | `recall` |
| `λ(evolve)` | `metabolize` |
| `instincts/personal/` | `mementum/memories/` |
| `instincts/library/` | `mementum/knowledge/` |
| Session state | `mementum/state.md` |
| Project facts | `mementum/knowledge/project-facts.md` |

## Key Insight

Skill wrappers add indirection without value. The protocol itself IS the knowledge. Store it in `mementum/knowledge/` and AI reads it via `orient()`.

## Architecture Simplified

```
Before: AGENTS.md → skills/ → SKILL.md → procedures → memories
After:  AGENTS.md → mementum/ → knowledge/protocol.md → direct execution
```

## When to Apply

- Any skill with procedural content → migrate to `mementum/knowledge/{domain}-protocol.md`
- Skills with state → use `mementum/state.md`
- Skills with instincts/patterns → use `mementum/memories/`