---
name: auto-workflow-researcher
description: OV5 consolidated — researcher prompt now lives in researcher-prompt/SKILL.md
version: OV5.1
---

# OV5.1 Consolidated

The active researcher prompt is defined in `assistant/skills/researcher-prompt/SKILL.md`.
This file is retained for legacy compatibility.

Research integration is now handled by:
- **Research coordinator**: ontology × AutoTTS × AutoGo → category research priorities
- **Auto-digestion**: research findings → structured mementum insights
- **Findings limiter**: strips `<think>` blocks, extracts actionable patterns, max 500 chars
- **Topic deduplication**: avoids re-researching the same topics across cycles
