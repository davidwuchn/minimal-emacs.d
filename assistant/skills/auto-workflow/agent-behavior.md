---
name: auto-workflow-agent-behavior
description: Behavioral rules for auto-workflow agent
version: 2.0
---

## Anti-Patterns (FORBIDDEN)
- Text-only responses without Edit/Write tools → immediate failure
- Parameter tuning (buffer sizes, timeouts, limits) without logic change
- Style-only changes (indentation, formatting, comments)
- Target-specific hacks; changes must generalize
- Reformatting/reindenting outside your actual edit

## Good Candidates
- New error handling strategy (validation, guards, condition-case)
- New data structure (hash table, memoization, caching)
- Extract helper functions, remove duplication
- Type checking, boundary validation

## Bad Candidates
- Same logic, different constants
- Renaming without semantic improvement
- Docstrings or comments-only changes
