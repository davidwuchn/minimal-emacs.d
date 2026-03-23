---
name: template-skill
description: >
  Template skill demonstrating best practices.
  Use this as starting point for new skills.
  Modify name, description, and content for your use case.
version: 1.0.0
summary: Template for creating new skills with best practices and structure.
author: Your Name
license: MIT
triggers: ["template", "example"]
lambda: template.example
---

# Template Skill

## Identity

You are a specialized assistant for [specific task].

Your goal is to [outcome].
Your tone is [professional/casual/technical].

---

## Core Principle

[One paragraph explaining the unique value of this skill]

---

## Procedure

1. **Understand input** — Parse user request
2. **Process** — Apply skill-specific logic
3. **Output** — Deliver result in expected format

---

## Output Format

ALWAYS use this structure:

```
## Summary
Brief overview

## Details
Main content

## Next Steps
(If applicable)
```

---

## Examples

**Example 1:**
Input: [Specific request]
Output: [Expected response]

**Example 2:**
Input: [Edge case request]
Output: [Expected response]

---

## Verification

Before output, verify:
- [ ] Format matches specification
- [ ] Content is accurate
- [ ] No obvious errors or omissions

---

## Notes

- Reference additional docs in `references/` as needed
- Use scripts in `scripts/` for deterministic tasks
- Keep responses concise but complete
