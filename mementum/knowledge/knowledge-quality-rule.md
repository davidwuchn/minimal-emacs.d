---
title: Knowledge Page Quality Rules
status: active
category: protocol
tags: [knowledge, synthesis, quality]
---

# Knowledge Page Quality Rules

Rules for creating useful knowledge pages, not stub placeholders.

## Minimum Requirements

A knowledge page MUST have:

1. **Minimum 50 lines** of actual content
2. **Concrete examples** (code, tables, commands)
3. **Actionable patterns** (not just "patterns identified from...")
4. **Cross-references** to related memories/knowledge

## Status Values

| Status | Meaning | Lines |
|--------|---------|-------|
| `open` | Work in progress | 20-49 |
| `active` | Complete and useful | 50+ |
| `done` | Stable, unlikely to change | 100+ |

## Anti-Pattern: Stub Pages

BAD (19 lines, useless):

```markdown
# cron

Synthesized from 5 memories.

## Key Patterns

Patterns identified from:
- cron-variable-expansion.md
- cron-scheduling-pattern.md
...
```

This is a placeholder, not knowledge. It wastes context.

GOOD (80+ lines, useful):

```markdown
# Cron-Based Scheduling for Auto-Workflow

## Platform-Specific Schedules

### macOS
0 10,14,18 * * * auto-workflow

### Linux/Pi5
0 23,3,7,11,15,19 * * * auto-workflow

## Cron Environment Setup

PATH=/opt/homebrew/bin:...
```

Contains actual patterns, examples, and solutions.

## Synthesis Protocol

When synthesizing memories into knowledge:

1. **READ** all listed memories
2. **EXTRACT** actual patterns, code, solutions
3. **WRITE** new content (not copy-paste)
4. **VERIFY** page is ≥50 lines
5. **SET** status to `active`

## Cleanup Rule

If knowledge page is <50 lines and >7 days old:

1. Either complete the synthesis
2. Or delete the stub

Stubs are technical debt, not assets.

## Related

- `mementum/knowledge/learning-protocol.md` - Memory creation
- `AGENTS.md` - Mementum protocol
