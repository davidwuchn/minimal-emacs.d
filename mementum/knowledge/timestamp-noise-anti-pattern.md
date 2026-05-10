---
title: Anti-Pattern — Timestamp Noise in Tracked Files
status: active
category: knowledge
tags: [git, anti-pattern, auto-generated, timestamp]
related: [mementum/knowledge/patterns.md]
depends-on: []
---

# Anti-Pattern: Timestamp Noise in Tracked Files

## Problem

Auto-generated files that include timestamps (e.g., `updated: 2026-05-10 15:38`) create meaningless git diffs on every regeneration, even when the actual content hasn't changed.

## Why It's Harmful

1. **Obscures real changes** — Every regeneration creates a commit, making it hard to see what actually changed
2. **Wastes git history** — Commits like "auto-workflow artifacts" with only timestamp changes pollute the log
3. **Merge conflicts** — Timestamp differences cause unnecessary merge conflicts
4. **Redundant information** — Git already tracks file modification times via `git log`

## Where It Occurred

- `assistant/skills/*/SKILL.md` — `updated:` field in YAML frontmatter
- `mementum/knowledge/experiment-insights-*.md` — `updated:` field in frontmatter
- `mementum/knowledge/auto-workflow-evolution.md` — `updated:` field in frontmatter

## Fix

**Remove `updated:` fields from auto-generated tracked files.**

Use `git log` when you need to know when a file was last modified:

```bash
# When was this file last modified?
git log -1 --format="%ai %s" -- path/to/file

# What changed in the last commit for this file?
git diff HEAD~1 -- path/to/file
```

## When Timestamps ARE Useful

- **Log files** (`var/log/*`) — Not tracked by git, timestamps essential for debugging
- **Cache files** (`var/tmp/*`) — Runtime needs to check staleness
- **Human-written docs** — Manual annotation of when content was reviewed

## Files Modified

- `lisp/modules/gptel-auto-workflow-evolution.el` — Removed `updated:` from SKILL.md and knowledge generation
- `lisp/modules/gptel-auto-workflow-mementum.el` — Removed `updated:` from evolution patterns synthesis

## Lesson

**Git already knows when files changed. Don't duplicate that information in file contents unless there's a specific runtime need.**
