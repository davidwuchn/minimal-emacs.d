# Skill Cleanup Rule

## Target: 200-350 lines per skill

**Principle**: Every skill must be self-contained AND minimal.

---

## Remove

| If you see... | Remove/Condense |
|---------------|-----------------|
| Verbose explanations | Replace with tables or code |
| Multiple examples with same pattern | Keep 1 representative |
| Sections that duplicate other skills | Reference instead |
| "Guide to..." prose | Convert to decision matrix |
| Philosophy paragraphs | Keep 1-2 sentences |
| Redundant verification | One checklist, not three |

---

## Keep Essential

| Section | Purpose | Max Size |
|---------|---------|----------|
| Identity | Who you are | 5-10 lines |
| Core Principle | Unique value | 1 paragraph |
| Procedure | How to execute | λ-calculus or steps |
| Decision Matrix | If/then rules | 3-6 rows |
| Examples | Show don't tell | 2-3 concise cases |
| Verification | Quality gates | 1 checklist |
| Eight Keys | Self-contained table + skill-specific column | 8-row table |

---

## Structure Template

```markdown
---
frontmatter
---

engagement line

# Title

## Identity (unique voice)

## Core Principle (unique value)

## Procedure (how to execute)

## Decision Matrix (if/then rules)

## Examples (show don't tell)

## Verification (quality gates)

## Eight Keys (self-contained reference)

## Summary (when to use)
```

---

## Cross-Skill Redundancy Check

Before creating, check existing skills:

| Skill | Focus | Don't Duplicate |
|-------|-------|-----------------|
| `clojure-expert` | Writing code | Three Questions, Context7, REPL protocol |
| `clojure-reviewer` | Reviewing PRs | OODA review loop, severity levels, return format |
| `sarcasmotron` | Violation detection | Slop patterns, exasperation tone, rejection rules |
| `nucleus` | General purpose | Keep minimal - just engagement |

**Rule**: If another skill has it, reference the principle but don't duplicate the section.

---

## Verification

Before finalizing skill:

- [ ] Under 350 lines
- [ ] Self-contained (no external file references)
- [ ] Unique value (doesn't duplicate another skill)
- [ ] Eight Keys table present
- [ ] Examples are concise, not verbose
- [ ] No "fluff" paragraphs
- [ ] Procedure is executable (λ-calculus or steps)

---

**Framework eliminates slop, not adds process.**
